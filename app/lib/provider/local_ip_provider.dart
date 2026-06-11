import 'dart:async';

import 'package:collection/collection.dart';
import 'package:common/util/network_interfaces.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/model/state/network_state.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:network_info_plus/network_info_plus.dart' as plugin;
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('NetworkInfo');

final localIpProvider = ReduxProvider<LocalIpService, NetworkState>((ref) {
  return LocalIpService(
    ref.notifier(settingsProvider),
  );
});

StreamSubscription? _subscription;

class LocalIpService extends ReduxNotifier<NetworkState> {
  final SettingsService _settingsService;

  LocalIpService(this._settingsService);

  @override
  NetworkState init() {
    return const NetworkState(
      localIps: [],
      initialized: false,
    );
  }

  @override
  get initialAction => InitLocalIpAction();
}

/// Fetches the local IP address and registers a listener to update the IP address
class InitLocalIpAction extends ReduxAction<LocalIpService, NetworkState> {
  @override
  NetworkState reduce() {
    if (!kIsWeb) {
      // ignore: discarded_futures
      _subscription?.cancel();

      if (checkPlatform([TargetPlatform.windows])) {
        // https://github.com/localsend/localsend/issues/12
        // https://github.com/localsend/localsend/issues/78
      } else {
        _subscription = Connectivity().onConnectivityChanged.listen((_) async {
          await dispatchAsync(FetchLocalIpAction());
        });
      }
    }

    return state;
  }

  @override
  void after() {
    // ignore: discarded_futures
    dispatchAsync(FetchLocalIpAction());
  }
}

class FetchLocalIpAction extends AsyncReduxAction<LocalIpService, NetworkState> {
  @override
  Future<NetworkState> reduce() async {
    return NetworkState(
      localIps: await _getIp(
        whitelist: notifier._settingsService.state.networkWhitelist,
        blacklist: notifier._settingsService.state.networkBlacklist,
        excludeVpnInterfaces: notifier._settingsService.state.networkExcludeVpnInterfaces,
      ),
      initialized: true,
    );
  }
}

Future<List<String>> _getIp({
  required List<String>? whitelist,
  required List<String>? blacklist,
  required bool excludeVpnInterfaces,
}) async {
  final info = plugin.NetworkInfo();
  String? ip;
  try {
    ip = await info.getWifiIP();
  } catch (e) {
    _logger.warning('Failed to get wifi IP', e);
  }

  final nativeResult =
      (await getNetworkInterfaces(
            whitelist: whitelist,
            blacklist: blacklist,
            excludeVpnInterfaces: excludeVpnInterfaces,
          ))
          .map((interface) => interface.addresses.map((a) => a.address).toList())
          .expand((ip) => ip)
          .where((ip) => !ip.contains(':')) // ignore IPv6 for now
          .toList();

  final addresses = rankIpAddresses(nativeResult, ip);
  _logger.info('Network state: $addresses');
  return addresses;
}

List<String> rankIpAddresses(List<String> nativeResult, String? thirdPartyResult) {
  if (thirdPartyResult == null) {
    return nativeResult._rankIpAddresses(null);
  } else if (nativeResult.isEmpty) {
    return [thirdPartyResult];
  }

  final merged = {thirdPartyResult, ...nativeResult}.toList();
  final primary = _resolvePrimaryIp(thirdPartyResult, nativeResult);
  return merged._rankIpAddresses(primary);
}

/// True for typical home/office WiFi addresses (192.168.x.x, excluding gateway and Android hotspot).
bool isPreferredHomeWifiIp(String ip) {
  if (ip.endsWith('.1') || ip.contains(':')) {
    return false;
  }

  final parts = ip.split('.');
  if (parts.length != 4) {
    return false;
  }

  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o! < 0 || o > 255)) {
    return false;
  }

  if (octets[0] != 192 || octets[1] != 168) {
    return false;
  }

  // Android mobile hotspot default range
  return octets[2] != 43;
}

/// Higher score = more suitable for LAN sharing (QR code, device discovery).
int lanIpPreferenceScore(String ip) {
  if (ip.endsWith('.1')) {
    return 0;
  }

  final parts = ip.split('.');
  if (parts.length != 4) {
    return 0;
  }

  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o! < 0 || o > 255)) {
    return 0;
  }

  final a = octets[0]!;
  final b = octets[1]!;
  final c = octets[2]!;

  if (a == 192 && b == 168) {
    return c == 43 ? 15 : 30;
  }

  if (a == 172 && b >= 16 && b <= 31) {
    return 20;
  }

  if (a == 10) {
    return 10;
  }

  return 1;
}

String? _resolvePrimaryIp(String wifiIp, List<String> nativeResult) {
  if (wifiIp.endsWith('.1')) {
    return null;
  }

  // getWifiIP() on Android may return cellular/VPN (e.g. 10.65.x.x) while WiFi is 192.168.x.x
  final hasHomeWifi = nativeResult.any(isPreferredHomeWifiIp);
  if (hasHomeWifi && !isPreferredHomeWifiIp(wifiIp)) {
    return null;
  }

  return wifiIp;
}

int _ipSortScore(String ip, String? primary) {
  if (ip == primary) {
    return 100;
  }
  return lanIpPreferenceScore(ip);
}

/// Sorts IP addresses with the first being the most likely reachable LAN address.
extension ListIpExt on List<String> {
  List<String> _rankIpAddresses(String? primary) {
    return sorted((a, b) => _ipSortScore(b, primary).compareTo(_ipSortScore(a, primary)));
  }
}
