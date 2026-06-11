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
  final int? maxUses; // null = unlimited uses
  final String? shareToken; // required token in URL for protected shares
  final DateTime? expiresAt; // auto-expire time
  final int useCount; // number of successful prepare-download accesses

  const WebSendState({
    required this.sessions,
    required this.files,
    required this.autoAccept,
    required this.pin,
    required this.pinAttempts,
    this.maxUses,
    this.shareToken,
    this.expiresAt,
    this.useCount = 0,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isUsesExhausted => maxUses != null && useCount >= maxUses!;

  bool get isInvalid => isExpired || isUsesExhausted;

  int? get remainingUses => maxUses != null ? maxUses! - useCount : null;

  @override
  String toString() {
    return 'WebSendState(sessions: $sessions, files: <${files.keys}>, autoAccept: $autoAccept, pin: $pin, pinAttempts: $pinAttempts, maxUses: $maxUses, shareToken: $shareToken, expiresAt: $expiresAt, useCount: $useCount)';
  }
}
