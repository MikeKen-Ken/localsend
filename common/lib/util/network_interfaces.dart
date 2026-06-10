import 'dart:io';

import 'package:logging/logging.dart';

final _logger = Logger('NetworkInterface');

/// Human-readable built-in VPN/proxy IPv4 ranges (for UI/docs).
const builtInVpnIpRanges = [
  '198.18.0.0/15 (Clash / Mihomo fake-ip)',
  '100.64.0.0/10 (Tailscale, etc.)',
  '10.8.0.0/16 (OpenVPN default pool)',
];

/// Returns a list of network interfaces respecting the whitelist and blacklist.
Future<List<NetworkInterface>> getNetworkInterfaces({
  required List<String>? whitelist,
  required List<String>? blacklist,
  bool excludeVpnInterfaces = false,
}) async {
  final result = <NetworkInterface>[];

  for (final interface in await NetworkInterface.list()) {
    if (isNetworkIgnoredRaw(
      networkWhitelist: whitelist,
      networkBlacklist: blacklist,
      interface: interface.addresses.map((a) => a.address).toList(),
      excludeVpnInterfaces: excludeVpnInterfaces,
    )) {
      _logger.info('Ignore network interface ${interface.name} (${interface.addresses.map((a) => a.address).toList()})');
      continue;
    }
    result.add(interface);
  }

  return result;
}

/// Returns true if the given IP should be ignored.
/// - When the IP is not in the whitelist (if the whitelist is not null)
/// - When the IP is in the blacklist (if the blacklist is not null)
/// - When any address matches a built-in VPN/proxy range (if [excludeVpnInterfaces] is true)
bool isNetworkIgnoredRaw({
  required List<String>? networkWhitelist,
  required List<String>? networkBlacklist,
  required List<String> interface,
  bool excludeVpnInterfaces = false,
}) {
  if (excludeVpnInterfaces && interface.any(isVpnIpAddress)) {
    return true;
  }

  return isNetworkIgnored(
    networkWhitelist: networkWhitelist?.map(buildRegExpFromIpFilter).toList(),
    networkBlacklist: networkBlacklist?.map(buildRegExpFromIpFilter).toList(),
    interface: interface,
  );
}

/// Returns true if the IPv4 address is in a commonly used VPN/proxy range.
///
/// Includes Clash / Mihomo default fake-ip (198.18.0.0/15).
bool isVpnIpAddress(String ip) {
  if (ip.contains(':')) {
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

  final a = octets[0]!;
  final b = octets[1]!;

  // Clash / Mihomo / sing-box fake-ip (default 198.18.0.0/16, extended /15)
  if (a == 198 && (b == 18 || b == 19)) {
    return true;
  }

  // Overlay VPNs such as Tailscale (RFC 6598)
  if (a == 100 && b >= 64 && b <= 127) {
    return true;
  }

  // OpenVPN default address pool
  if (a == 10 && b == 8) {
    return true;
  }

  return false;
}

/// Builds a regular expression from the given IP.
/// - '123.123.124.*' -> '^123\.123\.124\.[^.]+$'
/// - '1::1:*:3' -> '^1::1:[^.]+:3$'
RegExp buildRegExpFromIpFilter(String ip) {
  return RegExp('^${ip.replaceAll('.', '\\.').replaceAll('*', '[^.]+')}\$');
}

/// Returns true if the given IP should be ignored.
/// - When the IP is not in the whitelist (if the whitelist is not null)
/// - When the IP is in the blacklist (if the blacklist is not null)
bool isNetworkIgnored({
  required List<RegExp>? networkWhitelist,
  required List<RegExp>? networkBlacklist,
  required List<String> interface,
}) {
  if (networkWhitelist != null && !interface.any((a) => networkWhitelist.any((w) => w.hasMatch(a)))) {
    return true;
  }
  if (networkBlacklist != null && interface.any((a) => networkBlacklist.any((b) => b.hasMatch(a)))) {
    return true;
  }
  return false;
}
