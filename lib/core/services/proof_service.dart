import 'dart:io';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/proof.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Captures geo-tagged, timestamped proof images (PRD §4.3).
///
/// [CameraProofService] opens the real device camera (Rule 9); [StubProofService]
/// fabricates a proof record instead, kept around for tests / environments
/// without a camera (e.g. some emulator configurations).
abstract class ProofService {
  Future<Proof> capture(ProofKind kind);
}

/// Thrown when the user backs out of the camera without taking a photo.
class ProofCaptureCancelled implements Exception {}

/// Opens the phone's camera app (Rule 9) and returns the captured photo as a
/// geo-tagged, timestamped [Proof]. The photo is re-compressed before the
/// [Proof] is built — evidence photos are the largest thing this app ever
/// uploads, and field connectivity is often poor, so shrinking them here
/// (rather than uploading originals) matters more than for any other payload.
class CameraProofService implements ProofService {
  CameraProofService(this._location, this._config, [ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final LocationService _location;
  final ConfigService _config;
  final ImagePicker _picker;

  @override
  Future<Proof> capture(ProofKind kind) async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) throw ProofCaptureCancelled();
    final loc = await _location.currentLocation();
    final path = await _compress(file.path);
    return Proof(kind: kind, localPath: path, capturedAt: DateTime.now(), location: loc);
  }

  /// Re-encodes to `proof.imageMinWidthPx` / a JPEG quality tuned to land
  /// under `proof.imageMaxSizeMb`, retrying once at lower quality if the
  /// first pass is still oversized. Falls back to the original file if
  /// compression isn't available on this platform (e.g. some emulators).
  Future<String> _compress(String sourcePath) async {
    if (!_config.flag('features.compressUploads', fallback: true)) return sourcePath;
    final minWidth = _config.intValue('proof.imageMinWidthPx', fallback: 640);
    final maxBytes = _config.doubleValue('proof.imageMaxSizeMb', fallback: 5) * 1024 * 1024;
    final targetPath = '${sourcePath}_compressed.jpg';

    for (final quality in [70, 45]) {
      try {
        final result = await FlutterImageCompress.compressAndGetFile(
          sourcePath,
          targetPath,
          quality: quality,
          minWidth: minWidth,
          keepExif: false,
        );
        if (result == null) break;
        if (await File(result.path).length() <= maxBytes) return result.path;
      } catch (_) {
        break; // Compression plugin unavailable on this platform — use the original.
      }
    }
    return sourcePath;
  }
}

class StubProofService implements ProofService {
  StubProofService(this._location);

  final LocationService _location;
  int _counter = 0;

  @override
  Future<Proof> capture(ProofKind kind) async {
    final loc = await _location.currentLocation();
    _counter++;
    return Proof(
      kind: kind,
      localPath: 'mock://proof/${kind.name}_$_counter.jpg',
      capturedAt: DateTime.now(),
      location: loc,
    );
  }
}
