import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playtorrio/services/metadata/tvdb_series_service.dart';

void main() {
  final service = TvdbSeriesService.instance;
  tearDown(() {
    service.postOverride = null;
    service.getOverride = null;
  });

  test('TVDB verifies POST login and a separate authenticated metadata GET', () async {
    var loginCount = 0;
    var getCount = 0;
    service.postOverride = (uri, headers, body) async {
      loginCount++;
      expect(uri.path, '/v4/login');
      expect(jsonDecode(body)['apikey'], 'example-valid-key');
      expect(jsonDecode(body)['pin'], 'test-pin');
      return http.Response('{"data":{"token":"temporary-test-token"}}', 200);
    };
    service.getOverride = (uri, headers) async {
      getCount++;
      expect(uri.path, '/v4/search');
      expect(uri.queryParameters['type'], 'series');
      expect(headers['Authorization'], 'Bearer temporary-test-token');
      return http.Response('{"data":[]}', 200);
    };
    await service.validateCredentials('example-valid-key', 'test-pin');
    expect(loginCount, 1);
    expect(getCount, 1);
  });

  test('bad login rejects key before any metadata access', () async {
    var searched = false;
    service.postOverride = (_, __, ___) async => http.Response('{}', 401);
    service.getOverride = (_, __) async {
      searched = true;
      return http.Response('{"data":[]}', 200);
    };
    await expectLater(service.validateCredentials('bad-key', ''),
        throwsA(isA<FormatException>()));
    expect(searched, isFalse);
  });

  test('working login but forbidden metadata is not a valid usable key', () async {
    service.postOverride = (_, __, ___) async =>
        http.Response('{"data":{"token":"test-bearer"}}', 200);
    service.getOverride = (_, __) async => http.Response('{}', 403);
    await expectLater(service.validateCredentials('limited-key', ''),
        throwsA(isA<FormatException>()));
  });

  test('malformed metadata and missing token never pass validation', () async {
    service.postOverride = (_, __, ___) async =>
        http.Response('{"data":{"token":"test-bearer"}}', 200);
    service.getOverride = (_, __) async => http.Response('{"data":{}}', 200);
    await expectLater(service.validateCredentials('key', ''),
        throwsA(isA<FormatException>()));
    service.postOverride = (_, __, ___) async =>
        http.Response('{"data":{}}', 200);
    await expectLater(service.validateCredentials('key', ''),
        throwsA(isA<FormatException>()));
  });

  test('TVDB Settings validates before saving and exposes Test button', () {
    final file = File('lib/pages/settings/tvdb_settings_page.dart')
        .readAsStringSync();
    final check = file.indexOf('validateCredentials(');
    final save = file.indexOf('saveCredentials(');
    expect(check, greaterThanOrEqualTo(0));
    expect(save, greaterThan(check));
    expect(file, contains('Test TVDB key'));
    expect(file, contains('Existing saved key was not changed.'));
  });
}
