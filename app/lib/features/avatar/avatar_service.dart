import 'dart:io';
import 'dart:typed_data';

import 'package:common/api_route_builder.dart';
import 'package:path_provider/path_provider.dart';

const _avatarFileName = 'avatar.png';

/// 本地头像的存储、读取与 URL 解析。
abstract final class AvatarService {
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

  static String buildServeUrl({
    required String ip,
    required int port,
    required bool https,
  }) {
    final scheme = https ? 'https' : 'http';
    return '$scheme://$ip:$port${ApiRoute.avatar.v2}';
  }

  static String? resolveAvatarUrl({
    required String? externalAvatarUrl,
    required bool hasLocalAvatar,
    required String? localIp,
    required int? port,
    required bool https,
  }) {
    if (hasLocalAvatar && localIp != null && port != null && port > 0) {
      return buildServeUrl(ip: localIp, port: port, https: https);
    }

    final trimmed = externalAvatarUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
