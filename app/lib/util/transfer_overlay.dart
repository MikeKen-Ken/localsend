import 'package:common/model/session_status.dart';

/// Back from the progress page should keep an in-flight transfer instead of
/// minimizing the app or cancelling the session.
bool keepTransferAliveOnBack(SessionStatus? status) {
  return status == SessionStatus.sending || status == SessionStatus.finishedWithErrors;
}

enum TransferOverlayKind { send, receive }

class TransferOverlayTarget {
  final String sessionId;
  final TransferOverlayKind kind;
  final SessionStatus status;

  const TransferOverlayTarget({
    required this.sessionId,
    required this.kind,
    required this.status,
  });
}

bool _receiveOverlayVisible(SessionStatus status) {
  return status == SessionStatus.sending || status == SessionStatus.finished || status == SessionStatus.finishedWithErrors;
}

bool _sendOverlayVisible(SessionStatus status) {
  return status == SessionStatus.sending || status == SessionStatus.finishedWithErrors;
}

/// Picks the transfer shown as a bar on the home page after the user leaves progress.
TransferOverlayTarget? pickTransferOverlayTarget({
  required String? receiveSessionId,
  required SessionStatus? receiveStatus,
  required List<({String sessionId, SessionStatus status})> sendSessions,
}) {
  if (receiveSessionId != null && receiveStatus != null && _receiveOverlayVisible(receiveStatus)) {
    return TransferOverlayTarget(
      sessionId: receiveSessionId,
      kind: TransferOverlayKind.receive,
      status: receiveStatus,
    );
  }

  for (final session in sendSessions) {
    if (_sendOverlayVisible(session.status)) {
      return TransferOverlayTarget(
        sessionId: session.sessionId,
        kind: TransferOverlayKind.send,
        status: session.status,
      );
    }
  }

  return null;
}
