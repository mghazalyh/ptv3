import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// OAuth 2.0 PKCE (RFC 7636) for public Trakt client applications.
///
/// The verifier is ephemeral and is never written to disk or telemetry.
abstract final class TraktPkce {
  static String createVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String createState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String challenge(String verifier) {
    if (verifier.length < 43 || verifier.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(verifier)) {
      throw ArgumentError.value(null, 'verifier', 'Invalid PKCE verifier');
    }
    return base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
  }

  static Uri authorizationUrl({
    required String clientId,
    required String redirectUri,
    required String verifier,
    required String state,
  }) {
    return Uri.https('auth.trakt.tv', '/oauth/authorize', {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_challenge': challenge(verifier),
      'code_challenge_method': 'S256',
      'state': state,
    });
  }

  static Map<String, String> exchangeBody({
    required String clientId,
    required String redirectUri,
    required String code,
    required String verifier,
  }) {
    challenge(verifier);
    return {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code': code,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
    };
  }

  static Map<String, String> refreshBody({
    required String clientId,
    required String refreshToken,
    required String redirectUri,
    String legacyClientSecret = '',
  }) {
    return {
      'client_id': clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
      if (legacyClientSecret.isNotEmpty)
        'client_secret': legacyClientSecret
      else
        'redirect_uri': redirectUri,
    };
  }
}
