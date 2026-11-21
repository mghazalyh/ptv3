import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_media_diagnostic_request.dart';

void main() {
  test('Stremio series test uses exact episode-specific resource ID', () {
    final request = IosMediaDiagnosticRequest.parse({
      'type': 'series', 'id': 'tt1234567',
      'title': 'Example', 'season': 2, 'episode': 8,
    });
    expect(request.id, 'tt1234567');
    expect(request.streamId, 'tt1234567:2:8');
    expect(request.toJson()['episode'], 8);
  });

  test('Already episode-scoped ID is not duplicated', () {
    final request = IosMediaDiagnosticRequest.parse({
      'type': 'series', 'id': 'tt1234567:1:3',
      'title': 'Example', 'season': 1, 'episode': 3,
    });
    expect(request.streamId, 'tt1234567:1:3');
  });

  test('Episode coordinates cannot disagree with an already scoped ID', () {
    expect(() => IosMediaDiagnosticRequest.parse({
      'type': 'series', 'id': 'tt1234567:1:3',
      'title': 'Example', 'season': 2, 'episode': 3,
    }), throwsFormatException);
  });

  test('Movies and Live TV preserve resource identity', () {
    final movie = IosMediaDiagnosticRequest.parse({
      'type': 'movie', 'id': 'tt1234567', 'title': 'Film',
    });
    final tv = IosMediaDiagnosticRequest.parse({
      'type': 'tv', 'id': 'nltv:us:Example.us',
      'title': 'Example Channel',
    });
    expect(movie.streamId, 'tt1234567');
    expect(tv.streamId, 'nltv:us:Example.us');
    expect(movie.sourceIndex, 0);
    expect(movie.maxSources, 30);
  });

  test('Rejects missing season or episode and invalid source selection', () {
    expect(() => IosMediaDiagnosticRequest.parse({
      'type': 'series', 'id': 'tt1234567',
      'title': 'Example', 'season': 2,
    }), throwsFormatException);
    expect(() => IosMediaDiagnosticRequest.parse({
      'type': 'tv', 'id': 'arbitrary', 'title': 'Channel',
    }), throwsFormatException);
    expect(() => IosMediaDiagnosticRequest.parse({
      'type': 'movie', 'id': 'tt1234567',
      'title': 'Film', 'sourceIndex': -1,
    }), throwsFormatException);
  });
}
