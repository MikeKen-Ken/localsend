import 'dart:ui';

/// 修复 Windows 11 剪贴板历史（Win+V）选择后无法粘贴到 TextField 的问题。
///
/// Windows 会模拟 Ctrl+V 按键，但 Flutter Windows 嵌入层无法正确转换这些合成按键事件。
/// 参见：https://github.com/flutter/flutter/issues/143997
class WindowsClipboardHistoryFix {
  WindowsClipboardHistoryFix._();

  static bool _injecting = false;

  /// 在 [WidgetsFlutterBinding.ensureInitialized] 之后调用。
  static void install() {
    // 等待 Flutter 完成内置 onKeyData 回调注册
    Future<void>.delayed(const Duration(seconds: 1), _injectKeyData);
  }

  static void _injectKeyData() {
    final callback = PlatformDispatcher.instance.onKeyData;
    if (callback == null) {
      return;
    }

    PlatformDispatcher.instance.onKeyData = (data) {
      if (!_injecting &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.down &&
          !data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.down,
          physical: 0x700e0,
          logical: 0x200000100,
          character: null,
          synthesized: false,
        );
        _injecting = true;
      } else if (_injecting && data.physical == 0 && data.logical == 0 && data.type == KeyEventType.down && !data.synthesized) {
        return true;
      } else if (_injecting &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.up &&
          !data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.down,
          physical: 0x70019,
          logical: 0x76,
          character: null,
          synthesized: false,
        );
      } else if (_injecting &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.down &&
          data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.up,
          physical: 0x70019,
          logical: 0x76,
          character: null,
          synthesized: false,
        );
      } else if (_injecting &&
          data.physical == 0x1600000000 &&
          data.logical == 0x200000100 &&
          data.type == KeyEventType.up &&
          data.synthesized) {
        data = KeyData(
          timeStamp: data.timeStamp,
          type: KeyEventType.up,
          physical: 0x700e0,
          logical: 0x200000100,
          character: null,
          synthesized: false,
        );
        _injecting = false;
      } else {
        _injecting = false;
      }
      return callback(data);
    };
  }
}
