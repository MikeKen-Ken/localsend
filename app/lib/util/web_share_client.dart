import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:common/model/dto/receive_request_response_dto.dart';
import 'package:localsend_app/util/web_share_url.dart';

class WebSharePrepareResult {
  final int statusCode;
  final ReceiveRequestResponseDto? response;
  final String? message;

  const WebSharePrepareResult({
    required this.statusCode,
    this.response,
    this.message,
  });
}

class WebShareClient {
  HttpClient _createClient(String scheme) {
    final client = HttpClient();
    if (scheme == 'https') {
      client.badCertificateCallback = (_, __, ___) => true;
    }
    return client;
  }

  Future<WebSharePrepareResult> prepareDownload(
    WebShareUrl url, {
    String? pin,
  }) async {
    final client = _createClient(url.scheme);
    try {
      final uri = url.prepareDownloadUri(pinOverride: pin);
      final request = await client.postUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        return WebSharePrepareResult(
          statusCode: 200,
          response: ReceiveRequestResponseDtoMapper.fromJson(jsonDecode(body) as Map<String, dynamic>),
        );
      }

      String? message;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        message = json['message'] as String?;
      } catch (_) {
        message = body.isNotEmpty ? body : null;
      }

      return WebSharePrepareResult(
        statusCode: response.statusCode,
        message: message,
      );
    } on SocketException catch (e) {
      return WebSharePrepareResult(statusCode: 0, message: e.message);
    } on HttpException catch (e) {
      return WebSharePrepareResult(statusCode: 0, message: e.message);
    } finally {
      client.close(force: true);
    }
  }

  Stream<Uint8List> downloadStream(
    WebShareUrl url, {
    required String sessionId,
    required String fileId,
  }) async* {
    final client = _createClient(url.scheme);
    final uri = url.downloadUri(sessionId: sessionId, fileId: fileId);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})', uri: uri);
      }

      await for (final chunk in response) {
        yield Uint8List.fromList(chunk);
      }
    } finally {
      client.close(force: true);
    }
  }
}
