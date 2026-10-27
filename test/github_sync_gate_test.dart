import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playtorrio/services/continue_watching/github_sync_transport.dart';

void main() {
  setUp(GitHubSyncGate.resetForTesting);
  tearDown(GitHubSyncGate.resetForTesting);

  test('secondary 403 with Retry-After stops further GitHub operations', () {
    expect(() => GitHubSyncGate.inspect(http.Response(
      '{"message":"secondary rate limit"}', 403,
      headers: {'retry-after':'90'},
    )), throwsA(isA<GitHubSyncDeferred>()));
    expect(GitHubSyncGate.blockedUntil, isNotNull);
    expect(() => GitHubSyncGate.checkAllowed(),
        throwsA(isA<GitHubSyncDeferred>()));
  });

  test('remaining-zero 403 respects x-ratelimit-reset', () {
    final reset = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 180;
    expect(() => GitHubSyncGate.inspect(http.Response('', 403,
      headers: {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '$reset',
      },
    )), throwsA(isA<GitHubSyncDeferred>()));
  });

  test('validation 422 and true write conflicts 409 are not throttling', () {
    GitHubSyncGate.inspect(http.Response('{}', 422));
    GitHubSyncGate.inspect(http.Response('{}', 409));
    expect(GitHubSyncGate.blockedUntil, isNull);
  });

  test('primary/secondary 429 pauses even without a reset header', () {
    expect(() => GitHubSyncGate.inspect(http.Response('', 429)),
        throwsA(isA<GitHubSyncDeferred>()));
  });

  test('mutation failure does not poison the shared serial queue', () async {
    await expectLater(GitHubSyncGate.write(() async {
      throw StateError('network offline');
    }), throwsStateError);
    final reply = await GitHubSyncGate.write(
        () async => http.Response('{}', 200));
    expect(reply.statusCode, 200);
  });
}
