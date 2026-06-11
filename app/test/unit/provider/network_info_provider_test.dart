import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:test/test.dart';

void main() {
  group('rankIpAddresses', () {
    test('should only sort list if no primary', () {
      expect(rankIpAddresses(['123.456', '222.1', '321.222'], null), ['123.456', '321.222', '222.1']);
    });

    test('should only take primary', () {
      expect(rankIpAddresses([], '123.123'), ['123.123']);
    });

    test('should sort primary first', () {
      expect(rankIpAddresses(['123.456', '222.1', '321.222'], '123.123'), ['123.123', '123.456', '321.222', '222.1']);
    });

    test('should sort primary first and remove duplicates', () {
      expect(rankIpAddresses(['123.456', '123.123', '222.1', '222.1', '321.222'], '123.123'), ['123.123', '123.456', '321.222', '222.1']);
    });

    test('should prefer 192.168 over cellular/VPN 10.x when getWifiIP is wrong', () {
      expect(
        rankIpAddresses(['10.65.2.125', '192.168.1.100'], '10.65.2.125'),
        ['192.168.1.100', '10.65.2.125'],
      );
    });

    test('should keep 10.x primary when no 192.168 address exists', () {
      expect(
        rankIpAddresses(['10.0.0.10', '10.0.0.5'], '10.0.0.5'),
        ['10.0.0.5', '10.0.0.10'],
      );
    });

    test('should prefer 192.168 over 10.x and deprioritize gateway', () {
      expect(
        rankIpAddresses(['10.65.2.125', '192.168.1.100', '192.168.1.1'], null),
        ['192.168.1.100', '10.65.2.125', '192.168.1.1'],
      );
    });
  });
}
