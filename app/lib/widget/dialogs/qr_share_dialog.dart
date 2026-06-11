import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_state.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _QrShareState { initializing, active, expired, consumed, error }

class QrShareDialog extends StatefulWidget {
  final List<CrossFile> files;
  final int? maxUses;

  const QrShareDialog({
    required this.files,
    required this.maxUses,
  });

  static Future<void> open({
    required BuildContext context,
    required List<CrossFile> files,
    required int? maxUses,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => QrShareDialog(files: files, maxUses: maxUses),
    );
  }

  @override
  State<QrShareDialog> createState() => _QrShareDialogState();
}

class _QrShareDialogState extends State<QrShareDialog> with Refena {
  _QrShareState _state = _QrShareState.initializing;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      if (ref.read(serverProvider) == null) {
        await ref.notifier(serverProvider).startServerFromSettings();
      }

      await ref.notifier(serverProvider).initializeWebSend(
        widget.files,
        maxUses: widget.maxUses,
        quickShare: true,
      );

      if (!mounted) {
        return;
      }

      setState(() => _state = _QrShareState.active);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _QrShareState.error;
          _error = e.toString();
        });
      }
    }
  }

  void _onTick() {
    final webSendState = ref.read(serverProvider)?.webSendState;
    if (webSendState == null) {
      return;
    }

    if (webSendState.isUsesExhausted && _state == _QrShareState.active) {
      _timer?.cancel();
      setState(() => _state = _QrShareState.consumed);
      return;
    }

    if (webSendState.isExpired && _state == _QrShareState.active) {
      _timer?.cancel();
      setState(() => _state = _QrShareState.expired);
      ref.notifier(serverProvider).clearWebSend();
      return;
    }

    if (mounted && _state == _QrShareState.active) {
      setState(() {});
    }
  }

  void _close() {
    _timer?.cancel();
    final webSendState = ref.read(serverProvider)?.webSendState;
    final hasActiveSessions = webSendState?.sessions.values.any((session) => session.responseHandler == null) ?? false;
    if (!hasActiveSessions) {
      ref.notifier(serverProvider).clearWebSend();
    }
    if (mounted) {
      context.pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _buildShareUrl({
    required String ip,
    required int port,
    required bool https,
    required WebSendState webSendState,
  }) {
    final scheme = https ? 'https' : 'http';
    final uri = Uri(
      scheme: scheme,
      host: ip,
      port: port,
      queryParameters: {
        if (webSendState.shareToken != null) 'token': webSendState.shareToken!,
        if (webSendState.pin != null) 'pin': webSendState.pin!,
      },
    );
    return uri.toString();
  }

  String _formatRemaining(Duration remaining) {
    final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildUsesStatusChip(BuildContext context, WebSendState webSendState) {
    final maxUses = webSendState.maxUses;
    final label = maxUses == null
        ? t.dialogs.qr.usesStatusUnlimited
        : t.dialogs.qr.usesStatusLimited(
            remaining: webSendState.remainingUses ?? 0,
            total: maxUses,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _close();
      },
      child: AlertDialog(
        title: Text(t.dialogs.qr.shareTitle),
        content: _buildContent(context),
        actions: [
          TextButton(
            onPressed: _close,
            child: Text(t.general.close),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_state) {
      case _QrShareState.initializing:
        return const SizedBox(
          width: 200,
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        );
      case _QrShareState.error:
        return Text(_error ?? t.dialogs.qr.error);
      case _QrShareState.expired:
        return Text(
          t.dialogs.qr.expired,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.warning),
        );
      case _QrShareState.consumed:
        return Text(
          t.dialogs.qr.consumed,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.warning),
        );
      case _QrShareState.active:
        final serverState = context.watch(serverProvider);
        final webSendState = serverState?.webSendState;
        final networkState = context.watch(localIpProvider);
        final ip = networkState.localIps.firstOrNull;

        if (serverState == null || webSendState == null || ip == null) {
          return Text(t.dialogs.qr.error);
        }

        final httpSharePort = ref.notifier(serverProvider).httpSharePort;
        final useBrowserHttp = httpSharePort != null;
        final shareUrl = _buildShareUrl(
          ip: ip,
          port: useBrowserHttp ? httpSharePort! : serverState.port,
          https: useBrowserHttp ? false : serverState.https,
          webSendState: webSendState,
        );
        final remaining = webSendState.expiresAt!.difference(DateTime.now());

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUsesStatusChip(context, webSendState),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 220,
                height: 220,
                child: PrettyQrView.data(
                  errorCorrectLevel: QrErrorCorrectLevel.Q,
                  data: shareUrl,
                  decoration: PrettyQrDecoration(
                    shape: PrettyQrSmoothSymbol(
                      roundFactor: 0,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.dialogs.qr.expiresIn(time: _formatRemaining(remaining)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.warning,
              ),
            ),
            if (serverState.https && !useBrowserHttp) ...[
              const SizedBox(height: 8),
              Text(
                t.dialogs.qr.httpsBrowserWarning,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.warning,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              t.dialogs.qr.hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      shareUrl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: shareUrl));
                      if (context.mounted && checkPlatformIsDesktop()) {
                        context.showSnackBar(t.general.copiedToClipboard);
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.content_copy, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }
}
