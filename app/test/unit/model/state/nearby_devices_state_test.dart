import 'package:common/model/device.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:test/test.dart';

Device _device({
  required String fingerprint,
  String? avatarUrl,
  String ip = '192.168.1.10',
}) {
  return Device(
    signalingId: null,
    ip: ip,
    version: '2.1',
    port: 53317,
    https: true,
    fingerprint: fingerprint,
    alias: 'Phone',
    deviceModel: 'Pixel',
    avatarUrl: avatarUrl,
    deviceType: DeviceType.mobile,
    download: false,
    discoveryMethods: const {},
  );
}

void main() {
  test('mergeDiscoveredDevices keeps existing avatar when incoming omits it', () {
    final existing = _device(fingerprint: 'fp-1', avatarUrl: 'https://192.168.1.10:53317/api/localsend/v2/avatar');
    final incoming = _device(fingerprint: 'fp-1');

    expect(mergeDiscoveredDevices(incoming, existing).avatarUrl, existing.avatarUrl);
  });

  test('applyLastKnownAvatar fills a missing URL after a refresh wipe', () {
    final avatars = <String, String>{
      'fp-1': 'https://192.168.1.10:53317/api/localsend/v2/avatar?v=3',
    };
    final discovered = _device(fingerprint: 'fp-1');

    expect(
      applyLastKnownAvatar(discovered, avatars).avatarUrl,
      avatars['fp-1'],
    );
  });

  test('applyLastKnownAvatar does not override a fresh URL', () {
    final avatars = <String, String>{
      'fp-1': 'https://old.example/avatar',
    };
    final discovered = _device(fingerprint: 'fp-1', avatarUrl: 'https://192.168.1.10:53317/api/localsend/v2/avatar');

    expect(applyLastKnownAvatar(discovered, avatars).avatarUrl, discovered.avatarUrl);
  });

  test('rememberDeviceAvatarUrl ignores empty fingerprints and URLs', () {
    final avatars = <String, String>{};
    rememberDeviceAvatarUrl(_device(fingerprint: '', avatarUrl: 'https://x'), avatars);
    rememberDeviceAvatarUrl(_device(fingerprint: 'fp-1'), avatars);
    rememberDeviceAvatarUrl(_device(fingerprint: 'fp-1', avatarUrl: 'https://x/avatar'), avatars);

    expect(avatars, {'fp-1': 'https://x/avatar'});
  });
}
