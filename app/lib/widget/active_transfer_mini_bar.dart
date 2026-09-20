import 'package:common/model/device.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/progress_page.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/transfer_overlay.dart';
import 'package:localsend_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:localsend_app/widget/transfer_mini_panel.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Compact transfer bar on the home page. Opened by the system back gesture.
class ActiveTransferMiniBar extends StatelessWidget {
  final bool padBottomSafeArea;

  const ActiveTransferMiniBar({this.padBottomSafeArea = false});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final receiveSession = ref.watch(serverProvider.select((s) => s?.session));
    final sendSessions = ref.watch(sendProvider);
    final target = pickTransferOverlayTarget(
      receiveSessionId: receiveSession?.sessionId,
      receiveStatus: receiveSession?.status,
      sendSessions: sendSessions.values.map((s) => (sessionId: s.sessionId, status: s.status)).toList(),
    );
    if (target == null) {
      return const SizedBox.shrink();
    }

    final isReceive = target.kind == TransferOverlayKind.receive;
    final sendSession = isReceive ? null : sendSessions[target.sessionId];
    final Device? peerDevice = isReceive ? receiveSession?.sender : sendSession?.target;
    final peerName = isReceive
        ? receiveSession?.senderAlias
        : peerDevice == null
        ? null
        : ref.watch(favoritesProvider.select((state) => state.findDevice(peerDevice)))?.alias ?? peerDevice.alias;
    final files = isReceive
        ? receiveSession?.files.values.where((f) => f.status != FileStatus.skipped).map((f) => f.file).toList() ?? []
        : sendSession?.files.values.where((f) => f.status != FileStatus.skipped).map((f) => f.file).toList() ?? [];
    final progressNotifier = ref.watch(progressProvider);
    final currBytes = files.fold<int>(
      0,
      (prev, curr) => prev + ((progressNotifier.getProgress(sessionId: target.sessionId, fileId: curr.id) * curr.size).round()),
    );
    final totalBytes = files.fold<int>(0, (prev, curr) => prev + curr.size);
    final progress = totalBytes == 0 ? 0.0 : currBytes / totalBytes;
    final sending = target.status == SessionStatus.sending;
    final title = isReceive ? t.progressPage.titleReceiving : t.progressPage.titleSending;

    return TransferMiniPanel(
      title: title,
      peerDevice: peerDevice,
      peerName: peerName,
      statusLabel: _statusLabel(target.status),
      progress: progress,
      sending: sending,
      padBottomSafeArea: padBottomSafeArea,
      onRestore: () => _restore(context, target),
      onCancelOrDone: () => _cancelOrDone(context, target, sending: sending),
    );
  }
}

Future<void> _restore(BuildContext context, TransferOverlayTarget target) async {
  final ref = context.ref;
  if (target.kind == TransferOverlayKind.send) {
    ref.notifier(sendProvider).setBackground(target.sessionId, false);
  }
  await context.push(
    () => ProgressPage(
      showAppBar: true,
      closeSessionOnClose: false,
      sessionId: target.sessionId,
    ),
  );
  if (target.kind == TransferOverlayKind.send) {
    ref.notifier(sendProvider).setBackground(target.sessionId, true);
  }
}

Future<void> _cancelOrDone(BuildContext context, TransferOverlayTarget target, {required bool sending}) async {
  final ref = context.ref;
  if (sending) {
    final confirmed = (await context.pushBottomSheet(() => const CancelSessionDialog())) == true;
    if (!confirmed) {
      return;
    }
    if (target.kind == TransferOverlayKind.receive) {
      ref.notifier(serverProvider).cancelSession();
    } else {
      ref.notifier(sendProvider).cancelSession(target.sessionId);
    }
    return;
  }

  if (target.kind == TransferOverlayKind.receive) {
    ref.notifier(serverProvider).closeSession();
  } else {
    ref.notifier(sendProvider).closeSession(target.sessionId);
  }
}

String _statusLabel(SessionStatus status) {
  switch (status) {
    case SessionStatus.sending:
      return t.progressPage.total.title.sending(time: '-');
    case SessionStatus.finished:
      return t.general.finished;
    case SessionStatus.finishedWithErrors:
      return t.progressPage.total.title.finishedError;
    default:
      return '';
  }
}
