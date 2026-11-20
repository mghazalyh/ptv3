import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/lan_remote_service.dart';

void main() {
  group('LAN remote protocol', () {
    test('commands parse only known names', () {
      for (final command in LanRemoteCommand.values) {
        expect(LanRemoteProtocol.parseCommand(command.name), command);
      }
      expect(LanRemoteProtocol.parseCommand('eraseLibrary'), isNull);
      expect(LanRemoteProtocol.parseCommand('PlayPause'), isNull);
    });

    test('pairing code is exactly six digits', () {
      expect(LanRemoteProtocol.validCode('123456'), isTrue);
      expect(LanRemoteProtocol.validCode('000001'), isTrue);
      expect(LanRemoteProtocol.validCode('12345'), isFalse);
      expect(LanRemoteProtocol.validCode('1234567'), isFalse);
      expect(LanRemoteProtocol.validCode('abc456'), isFalse);
    });

    test('only local IPv4 addresses can be targeted', () {
      for (final address in [
        '192.168.1.8', '10.1.2.3', '172.16.0.1',
        '172.31.255.254', '169.254.1.1',
      ]) {
        expect(LanRemoteProtocol.validLanAddress(address), isTrue,
            reason: address);
      }
      for (final address in [
        '8.8.8.8', '127.0.0.1', '1.1.1.1', '172.32.0.1',
        'evil.example.com', '192.168.1.1:47891', '::1', '',
      ]) {
        expect(LanRemoteProtocol.validLanAddress(address), isFalse,
            reason: address);
      }
    });
  });
}
