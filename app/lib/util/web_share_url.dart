import 'package:common/constants.dart';

class WebShareUrl {
  final String scheme;
  final String host;
  final int port;
  final String? token;
  final String? pin;

  const WebShareUrl({
    required this.scheme,
    required this.host,
    required this.port,
    this.token,
    this.pin,
  });

  static WebShareUrl? tryParse(String input) {
    try {
      final uri = Uri.parse(input.trim());
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return null;
      }

      if (uri.host.isEmpty) {
        return null;
      }

      if (uri.path.isNotEmpty && uri.path != '/') {
        return null;
      }

      final port = uri.hasPort ? uri.port : defaultPort;

      return WebShareUrl(
        scheme: uri.scheme,
        host: uri.host,
        port: port,
        token: uri.queryParameters['token'],
        pin: uri.queryParameters['pin'],
      );
    } catch (_) {
      return null;
    }
  }

  Uri prepareDownloadUri({String? pinOverride}) {
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: '/api/localsend/v2/prepare-download',
      queryParameters: {
        if (token != null) 'token': token!,
        if (pinOverride != null) 'pin': pinOverride,
        if (pinOverride == null && pin != null) 'pin': pin!,
      },
    );
  }

  Uri downloadUri({required String sessionId, required String fileId}) {
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: '/api/localsend/v2/download',
      queryParameters: {
        'sessionId': sessionId,
        'fileId': fileId,
      },
    );
  }
}
