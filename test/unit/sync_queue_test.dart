import 'dart:async';
import 'dart:io';

import 'package:asset_recovery_app/core/services/api_client.dart'
    show ApiException;
import 'package:asset_recovery_app/core/services/attempt_record_sync.dart';
import 'package:asset_recovery_app/core/services/blob_upload_service.dart';
import 'package:asset_recovery_app/core/services/connectivity_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/data/repositories/mock_ticket_repository.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AttemptSubmission _submission({List<String> proofUrls = const []}) =>
    AttemptSubmission(
      id: 'a-1',
      ticketId: 'TKT-2026-00024',
      batteryId: 'INSMOMAH0001',
      agentId: 'SUNMU00002340',
      agentName: 'Ravi',
      attemptType: 'field_visit',
      outcome: 'recovered',
      attemptedAt: DateTime.utc(2026, 11, 5, 10),
      completedAt: DateTime.utc(2026, 11, 5, 10, 5),
      latitude: 12.97,
      longitude: 77.59,
      customerPresent: true,
      notes: 'ok',
      proofUrls: proofUrls,
      metadata: const {'k': 'v'},
    );

class _Repo extends MockTicketRepository {
  _Repo(this.onSubmit) : super(seed: 1, latency: Duration.zero);
  final Future<void> Function(AttemptSubmission) onSubmit;

  @override
  Future<void> submitAttemptRecord(AttemptSubmission submission) =>
      onSubmit(submission);
}

class _Blob implements BlobUploadService {
  _Blob({this.fail = false});
  static const configured = true;
  final bool fail;
  final uploaded = <String>[];

  @override
  bool get isConfigured => configured;

  @override
  Future<String> upload(File file,
      {required String blobName, String? contentType,}) async {
    if (fail) throw const SocketException('offline');
    uploaded.add(blobName);
    return 'https://blob.test/$blobName';
  }
}

void main() {
  late StubConnectivityService conn;
  late SyncQueueService queue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    conn = StubConnectivityService()..online = false;
    queue = SyncQueueService(
      conn,
      retryInitialDelay: const Duration(milliseconds: 20),
      retryMaxDelay: const Duration(milliseconds: 80),
    );
  });

  tearDown(() => queue.dispose());

  group('SyncQueueService', () {
    test('a successful replay removes the action', () async {
      var calls = 0;
      queue.registerHandler('t', (_) async => calls++);
      await queue.enqueue('t', {'x': 1});
      expect(queue.pendingCount, 1);
      await queue.drain();
      expect(calls, 1);
      expect(queue.pendingCount, 0);
    });

    test('a failing replay stays queued and is retried', () async {
      var calls = 0;
      queue.registerHandler('t', (_) async {
        calls++;
        if (calls == 1) throw const SocketException('offline');
      });
      await queue.enqueue('t', {});
      await queue.drain();
      expect(queue.pendingCount, 1, reason: 'kept after the failure');
      await queue.drain();
      expect(queue.pendingCount, 0);
      expect(calls, 2);
    });

    test('SyncDropException discards an action the server will never accept',
        () async {
      queue.registerHandler('t', (_) async => throw SyncDropException('422'));
      await queue.enqueue('t', {});
      await queue.drain();
      expect(queue.pendingCount, 0);
    });

    test('an action enqueued during a drain is not lost', () async {
      final gate = Completer<void>();
      queue.registerHandler('slow', (_) => gate.future);
      queue.registerHandler('late', (_) async {});
      await queue.enqueue('slow', {});
      final draining = queue.drain();
      await queue.enqueue('late', {});
      gate.complete();
      await draining;
      expect(queue.pendingCount, 1);
      await queue.drain();
      expect(queue.pendingCount, 0);
    });

    test('concurrent drains share one pass', () async {
      var calls = 0;
      final gate = Completer<void>();
      queue.registerHandler('t', (_) async {
        calls++;
        await gate.future;
      });
      await queue.enqueue('t', {});
      final a = queue.drain();
      final b = queue.drain();
      gate.complete();
      await Future.wait([a, b]);
      expect(calls, 1);
    });

    test('keeps retrying on its own once online, without a new trigger',
        () async {
      conn.online = true;
      var calls = 0;
      queue.registerHandler('t', (_) async {
        calls++;
        if (calls < 3) throw const SocketException('network not ready');
      });
      await queue.enqueue('t', {});
      // No further enqueue/connectivity event: the backoff timer must finish it.
      for (var i = 0; i < 50 && queue.pendingCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(queue.pendingCount, 0);
      expect(calls, 3);
    });
  });

  group('AttemptSubmission json', () {
    test('round-trips through toJson / fromJson', () {
      final original = _submission(proofUrls: const ['https://x/y.jpg']);
      final back = AttemptSubmission.fromJson(original.toJson());
      expect(back.toJson(), original.toJson());
      expect(back.id, 'a-1');
      expect(back.completedAt.isUtc, isTrue);
    });
  });

  group('AttemptRecordSync', () {
    test('replays a record once the network is back', () async {
      final sent = <AttemptSubmission>[];
      final sync = AttemptRecordSync(_Repo((s) async => sent.add(s)), _Blob());
      await sync(AttemptRecordSync.payload(_submission()));
      expect(sent.single.id, 'a-1');
      expect(sent.single.ticketId, 'TKT-2026-00024');
    });

    test('uploads queued photos first and adds their URLs', () async {
      final dir = Directory.systemTemp.createTempSync('ars');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}/p.jpg')..writeAsBytesSync([1, 2, 3]);
      final blob = _Blob();
      final sent = <AttemptSubmission>[];
      final sync = AttemptRecordSync(_Repo((s) async => sent.add(s)), blob);

      await sync(AttemptRecordSync.payload(
        _submission(proofUrls: const ['https://already/there.jpg']),
        pendingUploads: [
          {'localPath': photo.path, 'blobName': 'proofs/t/b/photo.jpg'},
        ],
      ),);

      expect(blob.uploaded, ['proofs/t/b/photo.jpg']);
      expect(sent.single.proofUrls, [
        'https://already/there.jpg',
        'https://blob.test/proofs/t/b/photo.jpg',
      ]);
    });

    test('a photo that no longer exists does not block the record', () async {
      final sent = <AttemptSubmission>[];
      final sync = AttemptRecordSync(_Repo((s) async => sent.add(s)), _Blob());
      await sync(AttemptRecordSync.payload(
        _submission(),
        pendingUploads: [
          {'localPath': '/no/such/file.jpg', 'blobName': 'x.jpg'},
        ],
      ),);
      expect(sent, hasLength(1));
      expect(sent.single.proofUrls, isEmpty);
    });

    test('still offline during upload: throws so the action stays queued',
        () async {
      final dir = Directory.systemTemp.createTempSync('ars');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
      final sync = AttemptRecordSync(
          _Repo((_) async => fail('must not post without the photo')),
          _Blob(fail: true),);
      await expectLater(
        sync(AttemptRecordSync.payload(_submission(), pendingUploads: [
          {'localPath': photo.path, 'blobName': 'x.jpg'},
        ],),),
        throwsA(isA<SocketException>()),
      );
    });

    test('a 4xx rejection drops the action; 5xx and 401 keep it', () async {
      Future<Object?> run(int status) async {
        final sync = AttemptRecordSync(
          _Repo((_) async => throw ApiException('x', statusCode: status)),
          _Blob(),
        );
        try {
          await sync(AttemptRecordSync.payload(_submission()));
        } catch (e) {
          return e;
        }
        return null;
      }

      expect(await run(422), isA<SyncDropException>());
      expect(await run(409), isA<SyncDropException>());
      expect(await run(500), isA<ApiException>());
      expect(await run(401), isA<ApiException>());
      expect(await run(429), isA<ApiException>());
    });

    test('a transport failure keeps the action queued', () async {
      final sync = AttemptRecordSync(
        _Repo((_) async => throw const SocketException('offline')),
        _Blob(),
      );
      await expectLater(
        sync(AttemptRecordSync.payload(_submission())),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
