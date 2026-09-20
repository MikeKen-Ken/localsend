import 'package:common/model/session_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/transfer_overlay.dart';

void main() {
  group('keepTransferAliveOnBack', () {
    test('keeps sending and error sessions so back can return to the previous page', () {
      expect(keepTransferAliveOnBack(SessionStatus.sending), isTrue);
      expect(keepTransferAliveOnBack(SessionStatus.finishedWithErrors), isTrue);
    });

    test('does not keep finished or cancelled sessions', () {
      expect(keepTransferAliveOnBack(SessionStatus.finished), isFalse);
      expect(keepTransferAliveOnBack(SessionStatus.canceledBySender), isFalse);
      expect(keepTransferAliveOnBack(null), isFalse);
    });
  });

  group('pickTransferOverlayTarget', () {
    test('prefers an in-flight receive session', () {
      final target = pickTransferOverlayTarget(
        receiveSessionId: 'recv',
        receiveStatus: SessionStatus.sending,
        sendSessions: [(sessionId: 'send', status: SessionStatus.sending)],
      );
      expect(target?.sessionId, 'recv');
      expect(target?.kind, TransferOverlayKind.receive);
    });

    test('falls back to a sending session after leaving progress', () {
      final target = pickTransferOverlayTarget(
        receiveSessionId: null,
        receiveStatus: null,
        sendSessions: [
          (sessionId: 'idle', status: SessionStatus.finished),
          (sessionId: 'active', status: SessionStatus.sending),
        ],
      );
      expect(target?.sessionId, 'active');
      expect(target?.kind, TransferOverlayKind.send);
    });

    test('hides the bar when nothing is transferring', () {
      expect(
        pickTransferOverlayTarget(
          receiveSessionId: null,
          receiveStatus: null,
          sendSessions: [(sessionId: 'done', status: SessionStatus.finished)],
        ),
        isNull,
      );
    });
  });
}
