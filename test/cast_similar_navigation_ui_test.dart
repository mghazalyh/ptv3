import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cast routes to PERSON credits instead of searching titles', () {
    final source = File('lib/pages/details/details_page.dart').readAsStringSync();
    expect(source, contains('PersonCreditsPage(actorName: name)'));
    expect(source, isNot(contains('DiscoverPage(query: name, isGenre: false)')));
    final person = File('lib/pages/details/person_credits_page.dart')
        .readAsStringSync();
    expect(person, contains('searchPeople(widget.actorName)'));
    expect(person, contains('personCombinedCredits(person.id)'));
    expect(person, contains('DetailsPage(movie: movie)'));
  });

  test('Similar Content exposes origin, original language, network or studio', () {
    final source = File('lib/pages/details/details_page.dart').readAsStringSync();
    expect(source, contains('enrichVisibleCards(result.items)'));
    expect(source, contains('Origin:'));
    expect(source, contains('Original:'));
    expect(source, contains("item.mediaType == 'movie' ? 'Studio' : 'Network'"));
    expect(source, contains('Not listed'));
  });
  test('Search and movie cards share Details recommendations and Load More', () {
    final search = File('lib/pages/search/search_page.dart').readAsStringSync();
    final slider = File('lib/widgets/movie/movie_slider_section.dart')
        .readAsStringSync();
    final card = File('lib/widgets/movie/movie_card.dart').readAsStringSync();
    final details = File('lib/pages/details/details_page.dart')
        .readAsStringSync();
    final service = File('lib/services/metadata/similar_recommendations_service.dart')
        .readAsStringSync();
    expect(search, contains('MovieSliderSection('));
    expect(slider, contains('MovieCard('));
    expect(card, contains('DetailsPage(movie: movie)'));
    expect(details, contains('SimilarRecommendationsService.load('));
    expect(details, contains('Recommended Movies'));
    expect(details, contains('Recommended Shows'));
    expect(details, contains("ValueKey('similar-load-more')"));
    expect(details, contains('SimilarRecommendationsService.loadMore('));
    expect(service, contains('DiscoverType.movie'));
    expect(service, contains('moreRelatedTitles('));
    expect(service, isNot(contains('if (!isSeries) return const SimilarRecommendationsResult([])')));
  });
  test('Similar Load More reveals a vertical grid and handles empty pages', () {
    final source = File('lib/pages/details/details_page.dart').readAsStringSync();
    final service = File('lib/services/metadata/similar_recommendations_service.dart')
        .readAsStringSync();
    expect(source, contains("ValueKey('similar-vertical-grid')"));
    expect(source, contains('GridView.builder('));
    expect(source, contains('NeverScrollableScrollPhysics()'));
    expect(source, isNot(contains('_similarScrollController.animateTo(target,')));
    expect(source, contains('pagesChecked < 2 && hasMore'));
    expect(source, contains('No more distinct recommendations are available.'));
    expect(source, contains('_similarLoadMoreEmpty = incoming.isEmpty;'));
    expect(service, contains('recordNoNewCards()'));
    expect(service, contains("_record('similar_load_more_empty');"));
  });

}
