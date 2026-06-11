import 'package:common/model/device.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'nearby_devices_state.mapper.dart';

@MappableClass()
class NearbyDevicesState with NearbyDevicesStateMappable {
  final bool runningFavoriteScan;
  final Set<String> runningIps; // list of local ips
  final Map<String, Device> devices; // ip -> device

  /// Devices that are discovered via signaling server.
  /// The key is the fingerprint of the device.
  /// We do not trust the fingerprint, so we allow multiple devices with the same fingerprint.
  final Map<String, Set<Device>> signalingDevices;

  const NearbyDevicesState({
    required this.runningFavoriteScan,
    required this.runningIps,
    required this.devices,
    required this.signalingDevices,
  });

  Map<String, Device> get allDevices {
    final Map<String, Device> allDevices = {};
    allDevices.addAll(devices);
    for (final devices in signalingDevices.values) {
      for (final device in devices) {
        final currentDevice = allDevices[device.fingerprint];
        if (currentDevice != null && currentDevice.alias == device.alias) {
          allDevices[device.fingerprint] = mergeDiscoveredDevices(device, currentDevice);
        } else {
          allDevices[device.fingerprint] = device;
        }
      }
    }
    return allDevices;
  }
}

/// Merges [incoming] over [existing], keeping non-null fields from [existing] when [incoming] omits them.
Device mergeDiscoveredDevices(Device incoming, Device existing) {
  return Device(
    signalingId: incoming.signalingId ?? existing.signalingId,
    ip: incoming.ip ?? existing.ip,
    version: incoming.version,
    port: incoming.port,
    https: incoming.https,
    fingerprint: incoming.fingerprint,
    alias: incoming.alias,
    deviceModel: incoming.deviceModel ?? existing.deviceModel,
    avatarUrl: incoming.avatarUrl ?? existing.avatarUrl,
    deviceType: incoming.deviceType,
    download: incoming.download,
    discoveryMethods: {
      ...existing.discoveryMethods,
      ...incoming.discoveryMethods,
    },
  );
}
