import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:common/isolate.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 本地头像版本号：0 表示无本地头像，>0 表示存在且每次保存递增（用于刷新缓存）。
final avatarLocalProvider = NotifierProvider<AvatarLocalService, int>(
  (ref) => AvatarLocalService(),
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
    state = (await AvatarService.hasLocalAvatar()) ? 1 : 0;
  }

  Future<void> saveCropped(Uint8List pngBytes, Ref ref) async {
    await AvatarService.saveCroppedAvatar(pngBytes);
    state = state > 0 ? state + 1 : 1;
    _triggerMulticast(ref);
  }

  Future<void> clear(Ref ref) async {
    await AvatarService.clearLocalAvatar();
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
