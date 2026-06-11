import 'dart:io';

import 'package:collection/collection.dart';
import 'package:localsend_app/features/avatar/avatar_provider.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/settings_provider.dart';

String? resolveAvatarUrlForRequest(ServerUtils server, HttpRequest request) {
  final settings = server.ref.read(settingsProvider);
  final state = server.getStateOrNull();
  if (state == null) {
    return settings.avatarUrl;
  }

  final port = request.uri.hasPort ? request.uri.port : state.port;
  final https = request.uri.scheme == 'https';

  return AvatarService.resolveAvatarUrl(
    externalAvatarUrl: settings.avatarUrl,
    hasLocalAvatar: server.ref.read(avatarLocalProvider) > 0,
    localAvatarRevision: server.ref.read(avatarLocalProvider),
    localIp: server.ref.read(localIpProvider).localIps.firstOrNull,
    port: port,
    https: https,
  );
}

String? resolveAvatarUrlForServer(ServerUtils server) {
  final settings = server.ref.read(settingsProvider);
  final state = server.getStateOrNull();
  if (state == null) {
    return settings.avatarUrl;
  }

  return AvatarService.resolveAvatarUrl(
    externalAvatarUrl: settings.avatarUrl,
    hasLocalAvatar: server.ref.read(avatarLocalProvider) > 0,
    localAvatarRevision: server.ref.read(avatarLocalProvider),
    localIp: server.ref.read(localIpProvider).localIps.firstOrNull,
    port: state.port,
    https: state.https,
  );
}
