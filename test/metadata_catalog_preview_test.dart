import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/movie.dart';
import 'package:playtorrio/services/metadata/metadata_service.dart';

void main() {
  test('catalog preview retains the real movie identity when meta fails', () {
    final movie = Movie(
      id: 'tt21285562',
      name: 'The Dog Stars',
      type: 'movie',
      addonBaseUrl: 'https://example.invalid',
      year: '2026',
      poster: 'https://example.invalid/poster.jpg',
    );
    final preview = MetadataService.previewForCatalog(movie);
    expect(preview.id, 'tt21285562');
    expect(preview.type, 'movie');
    expect(preview.name, 'The Dog Stars');
    expect(preview.year, '2026');
    expect(preview.poster, movie.poster);
    expect(preview.videos, isEmpty);
  });
}
