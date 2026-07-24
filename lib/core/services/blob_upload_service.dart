import 'dart:developer' as developer;
import 'dart:io';

import 'package:asset_recovery_app/core/config/environment.dart';
import 'package:azblob/azblob.dart';

/// Uploads captured proof images to remote object storage and returns the
/// stored object's URL.
///
/// Abstracted so the storage backend can change without touching call sites:
/// today it's Azure Blob Storage authenticated with the account key
/// ([AzureBlobUploadService]); when the backend exposes a short-lived SAS /
/// upload endpoint this is the seam where that swaps in, keeping the account
/// key out of the client.
abstract class BlobUploadService {
  /// Uploads [file]'s bytes to the configured container under [blobName]
  /// (which may contain `/` to create virtual folders) and returns the stored
  /// blob URL. Throws on failure.
  Future<String> upload(File file, {required String blobName, String? contentType});

  /// Whether credentials are present. When false, callers skip uploading
  /// (mock/test environments, or before the account key is filled in).
  bool get isConfigured;
}

/// Azure Blob Storage implementation. Uses the account connection string; the
/// `azblob` package signs every request with Shared Key (HMAC-SHA256), so no
/// SAS token or manual signing is required here.
class AzureBlobUploadService implements BlobUploadService {
  AzureBlobUploadService(this._config);

  final BlobStorageConfig _config;

  @override
  bool get isConfigured => _config.isConfigured;

  @override
  Future<String> upload(
    File file, {
    required String blobName,
    String? contentType,
  }) async {
    final storage = AzureStorage.parse(_config.connectionString);
    // Leading slash + container is the path shape azblob expects: `/container/blob`.
    final path = '/${_config.containerName}/$blobName';
    final url = storage.uri(path: path).toString();
    developer.log(
      'Uploading proof → container=${_config.containerName} path=$path url=$url',
      name: 'BlobUpload',
    );
    final bytes = await file.readAsBytes();
    await storage.putBlob(
      path,
      bodyBytes: bytes,
      contentType: contentType ?? _contentTypeFor(blobName),
    );
    developer.log('Upload complete → $url', name: 'BlobUpload');
    return url;
  }

  String _contentTypeFor(String blobName) {
    final lower = blobName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}

/// No-op used when blob credentials are absent (mock/test envs). [isConfigured]
/// is false so callers never invoke [upload]; it throws if they somehow do.
class NoopBlobUploadService implements BlobUploadService {
  const NoopBlobUploadService();

  @override
  bool get isConfigured => false;

  @override
  Future<String> upload(File file, {required String blobName, String? contentType}) async {
    throw StateError('Blob storage is not configured');
  }
}
