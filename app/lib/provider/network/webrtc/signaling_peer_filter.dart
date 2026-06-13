import 'package:localsend_app/rust/api/crypto.dart';
import 'package:localsend_app/rust/api/webrtc.dart';

/// 判断信令 peer 是否为当前设备（含残留的旧 WebRTC 会话）。
Future<bool> isSelfSignalingPeer({
  required ClientInfo peer,
  required ClientInfo? selfClient,
  required String publicKey,
}) async {
  if (selfClient != null && peer.id == selfClient.id) {
    return true;
  }

  return verifyToken(publicKey: publicKey, token: peer.token);
}
