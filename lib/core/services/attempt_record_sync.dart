import 'dart:developer' as developer;
import 'dart:io';

import 'package:asset_recovery_app/core/services/api_client.dart'
    show ApiException;
import 'package:asset_recovery_app/core/services/blob_upload_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';

/// Offline replay of a recovery-attempt record (`POST /attempts`).
///
/// This is the record the ticket detail's "Attempt history" is built from, so
/// when the send fails (no signal, timeout) it MUST be queued — before this
/// existed the failure was only logged and the attempt never reached the server.
///
/// A photo captured while offline never got a blob URL either, so the queued
/// payload also carries each still-unuploaded photo's local path and blob name.
/// Replay uploads those first, appends their URLs to `proofUrls`, then posts.
class AttemptRecordSync {
  AttemptRecordSync(this._repo, this._blob);

  /// [SyncQueueService] action type this handler is registered under.
  static const type = 'attempt_record';

  final TicketRepository _repo;
  final BlobUploadService _blob;

  /// Builds the queue payload for [submission]. [pendingUploads] are photos
  /// that have no blob URL yet: `{'localPath': ..., 'blobName': ...}`.
  static Map<String, dynamic> payload(
    AttemptSubmission submission, {
    List<Map<String, String>> pendingUploads = const [],
  }) =>
      {
        'submission': submission.toJson(),
        'uploads': pendingUploads,
      };

  /// True for responses that retrying can never fix: a client error other than
  /// the transient ones. 401 is excluded because the token is re-minted and the
  /// request retried, 408/429 because they clear on their own.
  static bool isPermanentRejection(int? statusCode) =>
      statusCode != null &&
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 401 &&
      statusCode != 408 &&
      statusCode != 429;

  /// Replays one queued action. Throws to stay queued, or [SyncDropException]
  /// when the server has definitively refused it.
  Future<void> call(Map<String, dynamic> queued) async {
    final json = Map<String, dynamic>.from(queued['submission'] as Map);
    final urls = List<String>.from(json['proofUrls'] as List? ?? const []);

    for (final raw in (queued['uploads'] as List? ?? const [])) {
      final upload = Map<String, dynamic>.from(raw as Map);
      final file = File(upload['localPath'] as String);
      if (!_blob.isConfigured || !file.existsSync()) {
        // The photo is gone (cache cleared) or storage isn't configured —
        // sending the record without it beats never sending the record.
        developer.log('Skipping photo ${upload['localPath']}',
            name: 'AttemptRecordSync',);
        continue;
      }
      // Same blob name overwrites, so a retry after a later failure is safe.
      urls.add(await _blob.upload(file, blobName: upload['blobName'] as String));
    }
    json['proofUrls'] = urls;

    try {
      await _repo.submitAttemptRecord(AttemptSubmission.fromJson(json));
    } on ApiException catch (e) {
      if (isPermanentRejection(e.statusCode)) {
        throw SyncDropException('HTTP ${e.statusCode}: ${e.message}');
      }
      rethrow;
    }
  }
}
