import 'package:common/constants.dart';
import 'package:common/model/device.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena/refena.dart';

/// Resolves [Device] instances for UI when only partial peer metadata is stored.
abstract final class DeviceResolver {
  static Device? findOnlineDevice(Ref ref, String fingerprint) {
    if (fingerprint.isEmpty) {
      return null;
    }
    return ref.read(nearbyDevicesProvider).allDevices[fingerprint];
  }

  static Device deviceForFavorite(Ref ref, FavoriteDevice favorite) {
    final https = ref.read(settingsProvider).https;
    final discovered = findOnlineDevice(ref, favorite.fingerprint);
    if (discovered != null) {
      if (favorite.customAlias) {
        return discovered.copyWith(alias: favorite.alias);
      }
      return discovered;
    }

    return Device(
      signalingId: null,
      ip: favorite.ip,
      version: protocolVersion,
      port: favorite.port,
      https: https,
      fingerprint: favorite.fingerprint,
      alias: favorite.alias,
      deviceModel: null,
      avatarUrl: null,
      deviceType: DeviceType.desktop,
      download: false,
      discoveryMethods: {HttpDiscovery(ip: favorite.ip)},
    );
  }

  static Device deviceForHistoryEntry(Ref ref, ReceiveHistoryEntry entry) {
    final fingerprint = entry.senderFingerprint;
    if (fingerprint != null && fingerprint.isNotEmpty) {
      final discovered = findOnlineDevice(ref, fingerprint);
      if (discovered != null) {
        return discovered.copyWith(alias: entry.senderAlias);
      }
    }

    return Device(
      signalingId: null,
      ip: null,
      version: protocolVersion,
      port: -1,
      https: false,
      fingerprint: fingerprint ?? '',
      alias: entry.senderAlias,
      deviceModel: null,
      avatarUrl: entry.senderAvatarUrl,
      deviceType: entry.senderDeviceType ?? DeviceType.desktop,
      download: false,
      discoveryMethods: const {},
    );
  }
}
