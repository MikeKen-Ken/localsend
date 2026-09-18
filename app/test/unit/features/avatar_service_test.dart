import 'dart:io';
import 'dart:typed_data';

import 'package:common/model/device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';

Device _device({
  String? ip = '192.168.1.42',
  String? avatarUrl,
  int port = 53317,
  bool https = true,
}) {
  return Device(
    signalingId: null,
    ip: ip,
    version: '2.1',
    port: port,
    https: https,
    fingerprint: 'fp',
    alias: 'Test',
    deviceModel: null,
    avatarUrl: avatarUrl,
    deviceType: DeviceType.mobile,
    download: false,
    discoveryMethods: const {},
  );
}

void main() {
  setUp(() {
    AvatarService.debugResetCaches();
    AvatarService.debugApplicationSupportDirectory = null;
  });

  tearDown(() {
    AvatarService.debugResetCaches();
    AvatarService.debugApplicationSupportDirectory = null;
  });

  test('normalizeAvatarUrlForDevice rewrites local avatar host to discovered IP', () {
    final device = _device(
      ip: '192.168.1.42',
      avatarUrl: 'https://10.0.0.5:53317/api/localsend/v2/avatar?v=2',
    );

    expect(
      AvatarService.normalizeAvatarUrlForDevice(device.avatarUrl!, device),
      'https://192.168.1.42:53317/api/localsend/v2/avatar?v=2',
    );
  });

  test('normalizeAvatarUrlForDevice leaves external URLs unchanged', () {
    final device = _device(
      ip: '192.168.1.42',
      avatarUrl: 'https://example.com/avatar.png',
    );

    expect(
      AvatarService.normalizeAvatarUrlForDevice(device.avatarUrl!, device),
      'https://example.com/avatar.png',
    );
  });

  test('resolveFetchUrl returns null when device has no avatar', () {
    final device = _device(ip: '192.168.1.42');

    expect(AvatarService.resolveFetchUrl(device), isNull);
  });

  test('resolveFetchUrl skips local avatar URLs when the peer has no IP', () {
    final device = _device(
      ip: null,
      avatarUrl: 'https://192.168.1.10:53317/api/localsend/v2/avatar',
    );

    expect(AvatarService.resolveFetchUrl(device), isNull);
  });

  test('peerAvatarFileName strips Windows-illegal characters', () {
    expect(AvatarService.peerAvatarFileName('ab/c:d*?'), 'peer_ab_c_d__.png');
    expect(AvatarService.peerAvatarFileName('  '), 'peer_unknown.png');
    expect(AvatarService.peerAvatarFileName('abc-123'), 'peer_abc-123.png');
  });

  test('savePeerAvatar can be reloaded after a process-local cache clear', () async {
    final dir = await Directory.systemTemp.createTemp('localsend_peer_avatar_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    AvatarService.debugApplicationSupportDirectory = dir;
    final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));

    await AvatarService.savePeerAvatar('fp-device-1', bytes);
    expect(AvatarService.getCachedPeerAvatarBytes('fp-device-1'), bytes);

    AvatarService.debugResetCaches();
    expect(AvatarService.getCachedPeerAvatarBytes('fp-device-1'), isNull);

    final loaded = await AvatarService.loadPeerAvatarBytes('fp-device-1');
    expect(loaded, bytes);
    expect(AvatarService.getCachedPeerAvatarBytes('fp-device-1'), bytes);
  });
}
