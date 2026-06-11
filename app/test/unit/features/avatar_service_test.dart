import 'package:common/model/device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';

Device _device({
  required String ip,
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
}
