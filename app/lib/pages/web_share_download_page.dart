import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/dto/receive_request_response_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/file_saver.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/util/web_share_client.dart';
import 'package:localsend_app/util/web_share_url.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

enum _PageState { loading, ready, downloading, finished, error }

class WebShareDownloadPage extends StatefulWidget {
  final WebShareUrl url;

  const WebShareDownloadPage({required this.url});

  @override
  State<WebShareDownloadPage> createState() => _WebShareDownloadPageState();
}

class _WebShareDownloadPageState extends State<WebShareDownloadPage> with Refena {
  final _client = WebShareClient();
  _PageState _state = _PageState.loading;
  ReceiveRequestResponseDto? _response;
  String? _error;
  final Map<String, double> _progress = {};
  final Set<String> _downloaded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare([String? pin]) async {
    setState(() {
      _state = _PageState.loading;
      _error = null;
    });

    final result = await _client.prepareDownload(widget.url, pin: pin);

    if (!mounted) {
      return;
    }

    if (result.statusCode == 401) {
      final enteredPin = await showDialog<String>(
        context: context,
        builder: (_) => PinDialog(
          obscureText: true,
          showInvalidPin: pin != null,
        ),
      );

      if (enteredPin != null && enteredPin.isNotEmpty) {
        await _prepare(enteredPin);
      } else {
        setState(() {
          _state = _PageState.error;
          _error = t.web.invalidPin;
        });
      }
      return;
    }

    if (result.statusCode != 200 || result.response == null) {
      setState(() {
        _state = _PageState.error;
        _error = switch (result.statusCode) {
          403 => t.dialogs.qr.expiredOrInvalid,
          429 => t.web.tooManyAttempts,
          0 => result.message ?? t.dialogs.qr.error,
          _ => result.message ?? t.dialogs.qr.error,
        };
      });
      return;
    }

    setState(() {
      _response = result.response;
      _state = _PageState.ready;
    });
  }

  Future<void> _downloadAll() async {
    final response = _response;
    if (response == null) {
      return;
    }

    setState(() => _state = _PageState.downloading);

    final destination = await getDefaultDestinationDirectory();
    final createdDirectories = <String>{};

    for (final entry in response.files.entries) {
      if (!mounted) {
        return;
      }

      await _downloadFile(
        file: entry.value,
        fileId: entry.key,
        sessionId: response.sessionId,
        destination: destination,
        createdDirectories: createdDirectories,
        senderAlias: response.info.alias,
      );
    }

    if (mounted) {
      setState(() => _state = _PageState.finished);
    }
  }

  Future<void> _downloadFile({
    required FileDto file,
    required String fileId,
    required String sessionId,
    required String destination,
    required Set<String> createdDirectories,
    required String senderAlias,
  }) async {
    try {
      final stream = _client.downloadStream(
        widget.url,
        sessionId: sessionId,
        fileId: fileId,
      );

      final (_, filePath) = await saveFile(
        destinationDirectory: destination,
        fileName: file.fileName,
        saveToGallery: false,
        isImage: file.fileType == FileType.image,
        stream: stream,
        onProgress: (savedBytes) {
          if (file.size != 0 && mounted) {
            setState(() {
              _progress[fileId] = savedBytes / file.size;
            });
          }
        },
        createdDirectories: createdDirectories,
      );

      if (filePath != null) {
        await ref.redux(receiveHistoryProvider).dispatchAsync(
          AddHistoryEntryAction(
            entryId: fileId,
            fileName: file.fileName,
            fileType: file.fileType,
            path: filePath,
            savedToGallery: false,
            isMessage: file.fileType == FileType.text,
            fileSize: file.size,
            senderAlias: senderAlias,
            timestamp: DateTime.now().toUtc(),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _progress[fileId] = 1;
          _downloaded.add(fileId);
        });
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('${file.fileName}: $e');
      }
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri(
      scheme: widget.url.scheme,
      host: widget.url.host,
      port: widget.url.port,
      queryParameters: {
        if (widget.url.token != null) 'token': widget.url.token!,
        if (widget.url.pin != null) 'pin': widget.url.pin!,
      },
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: basicLocalSendAppbar(t.dialogs.qr.downloadTitle),
      body: ResponsiveListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_state == _PageState.loading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 20),
            Center(child: Text(t.dialogs.qr.connecting)),
          ],
          if (_state == _PageState.error) ...[
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.warning),
            const SizedBox(height: 10),
            Text(_error ?? t.dialogs.qr.error, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: _openInBrowser,
                child: Text(t.dialogs.qr.openInBrowser),
              ),
            ),
          ],
          if (_response != null && _state != _PageState.loading && _state != _PageState.error) ...[
            Text(
              t.dialogs.qr.filesFrom(alias: _response!.info.alias),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ..._response!.files.entries.map((entry) {
              final file = entry.value;
              final progress = _progress[entry.key] ?? 0;
              final done = _downloaded.contains(entry.key);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.fileName, style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text(file.size.asReadableFileSize, style: Theme.of(context).textTheme.bodySmall),
                      if (_state == _PageState.downloading && !done) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress > 0 ? progress : null),
                      ],
                      if (done)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            t.general.finished,
                            style: TextStyle(color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            if (_state == _PageState.ready)
              ElevatedButton.icon(
                onPressed: _downloadAll,
                icon: const Icon(Icons.download),
                label: Text(t.dialogs.qr.downloadAll),
              ),
            if (_state == _PageState.finished)
              Text(
                t.dialogs.qr.downloadFinished,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            if (checkPlatformIsDesktop())
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: TextButton(
                    onPressed: _openInBrowser,
                    child: Text(t.dialogs.qr.openInBrowser),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
