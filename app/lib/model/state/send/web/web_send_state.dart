import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_app/model/state/send/web/web_send_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_session.dart';

part 'web_send_state.mapper.dart';

@MappableClass()
class WebSendState with WebSendStateMappable {
  final Map<String, WebSendSession> sessions; // session id -> session data, also includes incoming requests
  final Map<String, WebSendFile> files; // file id as key
  final bool autoAccept; // automatically accept incoming requests
  final String? pin;
  final Map<String, int> pinAttempts; // IP address -> attempts (will be reset on session end)
  final bool singleUse; // invalidate after first successful access
  final String? shareToken; // required token in URL for protected shares
  final DateTime? expiresAt; // auto-expire time
  final bool consumed; // true after first successful prepare-download in single-use mode

  const WebSendState({
    required this.sessions,
    required this.files,
    required this.autoAccept,
    required this.pin,
    required this.pinAttempts,
    this.singleUse = false,
    this.shareToken,
    this.expiresAt,
    this.consumed = false,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isInvalid => isExpired || (singleUse && consumed);

  @override
  String toString() {
    return 'WebSendState(sessions: $sessions, files: <${files.keys}>, autoAccept: $autoAccept, pin: $pin, pinAttempts: $pinAttempts, singleUse: $singleUse, shareToken: $shareToken, expiresAt: $expiresAt, consumed: $consumed)';
  }
}
