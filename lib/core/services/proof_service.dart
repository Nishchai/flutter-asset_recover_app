import 'dart:io';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/entities/proof.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Captures geo-tagged, timestamped proof artifacts (PRD §4.3) — a photo by
/// default, or, for a [FormFieldConfig.source] of `gallery`/`file`, whatever
/// that field picks instead (a photo-library screenshot, or an arbitrary file
/// such as an mp3/mp4 call recording).
///
/// [CameraProofService] opens the real device camera/picker (Rule 9);
/// [StubProofService] fabricates a proof record instead, kept around for
/// tests / environments without a camera (e.g. some emulator configurations).
abstract class ProofService {
  Future<Proof> capture(FormFieldConfig field);
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
  Future<Proof> capture(FormFieldConfig field) async {
    final kind = proofKindFromString(field.proofKind);
    final path = await _pickPath(field);
    if (path == null) throw ProofCaptureCancelled();
    final loc = await _location.currentLocation();
    return Proof(kind: kind, localPath: path, capturedAt: DateTime.now(), location: loc);
  }

  /// Picks the source file per [FormFieldConfig.source]: the camera (default,
  /// also compressed per [_compress]), the photo library (`gallery`), or a
  /// file restricted to [FormFieldConfig.fileType]/[FormFieldConfig.acceptExtensions]
  /// (`file`, e.g. an audio-only call recording — never compressed). Null
  /// means the agent backed out of the picker.
  Future<String?> _pickPath(FormFieldConfig field) async {
    if (field.source == 'file') {
      final type = _fileTypeFor(field);
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: type == FileType.custom ? field.acceptExtensions : null,
      );
      return result?.files.single.path;
    }
    final imageSource =
        field.source == 'gallery' ? ImageSource.gallery : ImageSource.camera;
    final file = await _picker.pickImage(source: imageSource, imageQuality: 85);
    if (file == null) return null;
    return _compress(file.path);
  }

  /// The system picker's own type filter — e.g. `audio` rejects a video file
  /// outright (by its real type, not just its extension), which a
  /// [FormFieldConfig.acceptExtensions] allow-list can't guarantee on its own.
  /// Falls back to `custom` (extension allow-list) when [FormFieldConfig.fileType]
  /// isn't set, or `any` when neither is.
  FileType _fileTypeFor(FormFieldConfig field) {
    switch (field.fileType) {
      case 'audio':
        return FileType.audio;
      case 'video':
        return FileType.video;
      case 'image':
        return FileType.image;
      case 'media':
        return FileType.media;
      case 'custom':
        return FileType.custom;
      default:
        return field.acceptExtensions == null ? FileType.any : FileType.custom;
    }
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
  Future<Proof> capture(FormFieldConfig field) async {
    final kind = proofKindFromString(field.proofKind);
    final loc = await _location.currentLocation();
    _counter++;
    final ext = field.source == 'file' ? (field.acceptExtensions?.first ?? 'mp3') : 'jpg';
    return Proof(
      kind: kind,
      localPath: 'mock://proof/${kind.name}_$_counter.$ext',
      capturedAt: DateTime.now(),
      location: loc,
    );
  }
}
