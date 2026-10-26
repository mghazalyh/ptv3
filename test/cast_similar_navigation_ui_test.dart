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
}
