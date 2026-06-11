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

  // HttpRequest.uri often omits host/port/scheme; use the socket the request arrived on.
  final localIps = server.ref.read(localIpProvider).localIps;
  final localPort = request.connectionInfo?.localPort ?? state.port;
  final localIp = _resolveLocalIpForConnection(request, localIps);
  final https = state.https && localPort == state.port;

  return AvatarService.resolveAvatarUrl(
    externalAvatarUrl: settings.avatarUrl,
    hasLocalAvatar: server.ref.read(avatarLocalProvider) > 0,
    localAvatarRevision: server.ref.read(avatarLocalProvider),
    localIp: localIp,
    port: localPort,
    https: https,
  );
}

/// Picks the local IP that best matches the socket [request] arrived on.
///
/// `HttpConnectionInfo` no longer exposes `localAddress`; infer from the client's
/// remote address and our known LAN interfaces (same /24 prefix).
String? _resolveLocalIpForConnection(HttpRequest request, List<String> localIps) {
  if (localIps.isEmpty) {
    return null;
  }
  if (localIps.length == 1) {
    return localIps.first;
  }

  final remoteIp = request.connectionInfo?.remoteAddress.address;
  if (remoteIp == null || remoteIp.contains(':')) {
    return localIps.firstOrNull;
  }

  final remotePrefix = remoteIp.split('.').take(3).join('.');
  return localIps
          .where((ip) => !ip.contains(':') && ip.split('.').take(3).join('.') == remotePrefix)
          .firstOrNull ??
      localIps.firstOrNull;
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
