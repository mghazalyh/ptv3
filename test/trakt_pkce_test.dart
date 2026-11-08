import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/trakt/trakt_pkce.dart';

void main() {
  const redirect = 'http://localhost:8080/callback';

  test('RFC 7636 S256 reference challenge', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    expect(TraktPkce.challenge(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });

  test('random verifier/state are distinct, URL-safe and sufficiently long', () {
    final first = TraktPkce.createVerifier();
    final second = TraktPkce.createVerifier();
    final state = TraktPkce.createState();
    expect(first.length, inInclusiveRange(43, 128));
    expect(RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(first), isTrue);
    expect(first, isNot(second));
    expect(state.length, greaterThanOrEqualTo(32));
    expect(state, isNot(TraktPkce.createState()));
  });

  test('authorization URL includes state, S256 and exact callback', () {
    final verifier = TraktPkce.createVerifier();
    final url = TraktPkce.authorizationUrl(
        clientId: 'test-client', redirectUri: redirect,
        verifier: verifier, state: 'unguessable-state');
    expect(url.scheme, 'https');
    expect(url.host, 'auth.trakt.tv');
    expect(url.queryParameters['client_id'], 'test-client');
    expect(url.queryParameters['redirect_uri'], redirect);
    expect(url.queryParameters['state'], 'unguessable-state');
    expect(url.queryParameters['response_type'], 'code');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['code_challenge'], TraktPkce.challenge(verifier));
    expect(url.queryParameters.containsKey('client_secret'), isFalse);
  });

  test('code exchange and refresh never require a client secret', () {
    final verifier = TraktPkce.createVerifier();
    final exchange = TraktPkce.exchangeBody(
        clientId: 'test-client', redirectUri: redirect,
        code: 'test-code', verifier: verifier);
    expect(exchange['code_verifier'], verifier);
    expect(exchange['grant_type'], 'authorization_code');
    expect(exchange.containsKey('client_secret'), isFalse);

    final refresh = TraktPkce.refreshBody(
        clientId: 'test-client', refreshToken: 'test-refresh',
        redirectUri: redirect);
    expect(refresh['grant_type'], 'refresh_token');
    expect(refresh['redirect_uri'], redirect);
    expect(refresh.containsKey('client_secret'), isFalse);
  });

  test('malformed PKCE verifiers are rejected', () {
    expect(() => TraktPkce.challenge('short'), throwsArgumentError);
    expect(() => TraktPkce.challenge(List.filled(129, 'a').join()),
        throwsArgumentError);
  });
}
