import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/transfer_window_compact.dart';

void main() {
  test('mini transfer window is smaller than the restored minimum', () {
    expect(TransferWindowCompact.miniSize.width, lessThanOrEqualTo(TransferWindowCompact.restoredMinimum.width + 20));
    expect(TransferWindowCompact.miniSize.height, lessThan(TransferWindowCompact.restoredMinimum.height));
    expect(TransferWindowCompact.miniSize.height, lessThan(200));
  });
}
