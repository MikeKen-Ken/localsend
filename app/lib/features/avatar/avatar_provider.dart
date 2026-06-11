import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:common/isolate.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 本地头像版本号：0 表示无本地头像，>0 表示存在且每次保存递增（用于刷新网络 URL 缓存）。
final avatarLocalProvider = NotifierProvider<AvatarLocalService, int>(
  (ref) => AvatarLocalService(),
);

/// 本地头像 PNG 字节缓存，仅在保存/清除/启动加载时更新，避免 UI 重建时重复读盘闪烁。
final avatarLocalBytesProvider = NotifierProvider<AvatarLocalBytesService, Uint8List?>(
  (ref) => AvatarLocalBytesService(),
);

/// 解析后的头像 URL（本地文件优先，否则使用外部 URL）。
final avatarResolvedUrlProvider = ViewProvider<String?>(
  (ref) {
    ref.watch(avatarLocalProvider);
    ref.watch(localIpProvider);
    ref.watch(serverProvider);
    final (externalUrl, https) = ref.watch(settingsProvider.select((s) => (s.avatarUrl, s.https)));
    final server = ref.read(serverProvider);
    return AvatarService.resolveAvatarUrl(
      externalAvatarUrl: externalUrl,
      hasLocalAvatar: ref.read(avatarLocalProvider) > 0,
      localAvatarRevision: ref.read(avatarLocalProvider),
      localIp: ref.read(localIpProvider).localIps.firstOrNull,
      port: server?.port,
      https: server?.https ?? https,
    );
  },
  onChanged: (_, next, ref) {
    final syncState = ref.read(parentIsolateProvider).syncState;
    if (syncState.avatarUrl == next) {
      return;
    }
    ref.redux(parentIsolateProvider).dispatch(
          IsolateSyncServerStateAction(
            alias: syncState.alias,
            avatarUrl: next,
            port: syncState.port,
            protocol: syncState.protocol,
            serverRunning: syncState.serverRunning,
            download: syncState.download,
          ),
        );
    if (syncState.serverRunning) {
      ref.redux(parentIsolateProvider).dispatch(IsolateSendMulticastAnnouncementAction());
    }
  },
);

class AvatarLocalService extends Notifier<int> {
  @override
  int init() {
    unawaited(_refresh());
    return 0;
  }

  Future<void> _refresh() async {
    final exists = await AvatarService.hasLocalAvatar();
    state = exists ? 1 : 0;
    if (exists) {
      ref.notifier(avatarLocalBytesProvider).setBytes(await AvatarService.readLocalAvatarBytes());
    } else {
      ref.notifier(avatarLocalBytesProvider).clear();
    }
  }

  Future<void> saveCropped(Uint8List pngBytes, Ref ref) async {
    await AvatarService.saveCroppedAvatar(pngBytes);
    ref.notifier(avatarLocalBytesProvider).setBytes(pngBytes);
    state = state > 0 ? state + 1 : 1;
    _triggerMulticast(ref);
  }

  Future<void> clear(Ref ref) async {
    await AvatarService.clearLocalAvatar();
    ref.notifier(avatarLocalBytesProvider).clear();
    state = 0;
    _triggerMulticast(ref);
  }

  void _triggerMulticast(Ref ref) {
    ref.read(avatarResolvedUrlProvider);
    final syncState = ref.read(parentIsolateProvider).syncState;
    if (syncState.serverRunning) {
      ref.redux(parentIsolateProvider).dispatch(IsolateSendMulticastAnnouncementAction());
    }
  }
}

class AvatarLocalBytesService extends Notifier<Uint8List?> {
  @override
  Uint8List? init() => null;

  void setBytes(Uint8List? bytes) {
    state = bytes;
  }

  void clear() {
    state = null;
  }
}
