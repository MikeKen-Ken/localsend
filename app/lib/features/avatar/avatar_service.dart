import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:common/api_route_builder.dart';
import 'package:common/model/device.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const _avatarFileName = 'avatar.png';
const _remoteAvatarTimeout = Duration(seconds: 3);

/// 本地头像的存储、读取与 URL 解析。
abstract final class AvatarService {
  static final Map<String, Uint8List> _remoteAvatarCache = {};
  static final Map<String, Future<Uint8List?>> _remoteAvatarInFlight = {};

  static Future<File> get _avatarFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_avatarFileName');
  }

  static Future<bool> hasLocalAvatar() async {
    return (await _avatarFile).existsSync();
  }

  static Future<Uint8List?> readLocalAvatarBytes() async {
    final file = await _avatarFile;
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsBytes();
  }

  static Future<File?> getLocalAvatarFile() async {
    final file = await _avatarFile;
    if (!file.existsSync()) {
      return null;
    }
    return file;
  }

  static Future<void> saveCroppedAvatar(Uint8List pngBytes) async {
    final file = await _avatarFile;
    await file.writeAsBytes(pngBytes, flush: true);
  }

  static Future<void> clearLocalAvatar() async {
    final file = await _avatarFile;
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static Future<Uint8List?> fetchUrlImageBytes(String url, {bool forceRefresh = false}) async {
    final normalizedUrl = url.trim();
    if (!forceRefresh) {
      final cached = _remoteAvatarCache[normalizedUrl];
      if (cached != null) {
        return cached;
      }

      final inFlight = _remoteAvatarInFlight[normalizedUrl];
      if (inFlight != null) {
        return inFlight;
      }
    }

    final future = _fetchUrlImageBytesUncached(normalizedUrl);
    _remoteAvatarInFlight[normalizedUrl] = future;
    try {
      final bytes = await future;
      if (bytes != null) {
        _remoteAvatarCache[normalizedUrl] = bytes;
      }
      return bytes;
    } finally {
      _remoteAvatarInFlight.remove(normalizedUrl);
    }
  }

  static Uint8List? getCachedRemoteAvatarBytes(String url) {
    return _remoteAvatarCache[url.trim()];
  }

  static void evictRemoteAvatar(String url) {
    _remoteAvatarCache.remove(url.trim());
  }

  static Future<Uint8List?> _fetchUrlImageBytesUncached(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    final client = HttpClient()..connectionTimeout = _remoteAvatarTimeout;
    if (isLocalServeUrl(uri)) {
      client.badCertificateCallback = (_, __, ___) => true;
    }
    try {
      final request = await client.getUrl(uri).timeout(_remoteAvatarTimeout);
      final response = await request.close().timeout(_remoteAvatarTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      return await consolidateHttpClientResponseBytes(response).timeout(_remoteAvatarTimeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// LocalSend serves avatars from the device HTTP(S) server (self-signed TLS).
  static bool isLocalServeUrl(Uri uri) {
    return uri.path.contains(ApiRoute.avatar.v2) || uri.path.contains(ApiRoute.avatar.v1);
  }

  /// Resolves the URL used to fetch a peer avatar.
  ///
  /// Announcements may embed [Device.ip] from another interface (VPN/TUN, multi-NIC).
  /// Rewrite local avatar URLs to the IP we actually use to reach the device.
  static String? resolveFetchUrl(Device device) {
    final raw = device.avatarUrl?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return normalizeAvatarUrlForDevice(raw, device);
  }

  static String normalizeAvatarUrlForDevice(String avatarUrl, Device device) {
    final uri = Uri.tryParse(avatarUrl.trim());
    if (uri == null || !isLocalServeUrl(uri)) {
      return avatarUrl.trim();
    }

    final ip = device.ip;
    if (ip == null || ip.isEmpty || ip == '-') {
      return avatarUrl.trim();
    }

    final port = device.port > 0 ? device.port : uri.port;
    final scheme = device.https ? 'https' : 'http';

    return Uri(
      scheme: scheme,
      host: ip,
      port: port,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }

  static String buildServeUrl({
    required String ip,
    required int port,
    required bool https,
    int? revision,
  }) {
    final scheme = https ? 'https' : 'http';
    final url = '$scheme://$ip:$port${ApiRoute.avatar.v2}';
    if (revision != null && revision > 0) {
      return '$url?v=$revision';
    }
    return url;
  }

  static String? resolveAvatarUrl({
    required String? externalAvatarUrl,
    required bool hasLocalAvatar,
    required String? localIp,
    required int? port,
    required bool https,
    int localAvatarRevision = 0,
  }) {
    if (hasLocalAvatar && localIp != null && port != null && port > 0) {
      return buildServeUrl(ip: localIp, port: port, https: https, revision: localAvatarRevision);
    }

    final trimmed = externalAvatarUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
