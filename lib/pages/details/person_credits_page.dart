import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/metadata/tmdb_discover_service.dart';
import 'details_page.dart';
import '../../services/metadata/title_origin_language_service.dart';

/// Clicking Cast means filmography, never searching titles for a person's name.
class PersonCreditsPage extends StatefulWidget {
  final String actorName;
  const PersonCreditsPage({super.key, required this.actorName});

  @override
  State<PersonCreditsPage> createState() => _PersonCreditsPageState();
}

class _PersonCreditsPageState extends State<PersonCreditsPage> {
  final _tmdb = TmdbDiscoverService.instance;
  late Future<List<TmdbPerson>> _people;
  Future<List<DiscoverTitle>>? _credits;
  TmdbPerson? _person;
  int? _openingId;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _people = _tmdb.searchPeople(widget.actorName);
  }

  void _select(TmdbPerson person) {
    setState(() {
      _person = person;
      _credits = _tmdb.personCombinedCredits(person.id);
      _openError = null;
    });
  }

  Future<void> _open(DiscoverTitle title) async {
    if (_openingId != null) return;
    setState(() { _openingId = title.tmdbId; _openError = null; });
    try {
      final movie = await _tmdb.resolveMovie(title);
      if (!mounted) return;
      if (movie == null) {
        setState(() => _openError =
            'No IMDb/Stremio match was found for this credit.');
        return;
      }
      await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => DetailsPage(movie: movie)));
    } catch (_) {
      if (mounted) setState(() => _openError =
          'Could not open this credit. Check your network connection.');
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Widget _personChoice(TmdbPerson person) => Card(
    child: ListTile(
      leading: CircleAvatar(
        foregroundImage: person.photo == null
            ? null : CachedNetworkImageProvider(person.photo!),
        child: person.photo == null ? const Icon(Icons.person_outline) : null,
      ),
      title: Text(person.name),
      subtitle: Text(person.department.isEmpty
          ? 'View movie and TV credits' : person.department),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _select(person),
    ),
  );

  Widget _creditsGrid(List<DiscoverTitle> items) {
    if (items.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('No credited movies or TV shows are listed for this person.'),
      ));
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 1100 ? 6 : box.maxWidth > 750 ? 5
          : box.maxWidth > 480 ? 3 : 2;
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, crossAxisSpacing: 10,
          mainAxisSpacing: 10, childAspectRatio: 0.49,
        ),
        itemBuilder: (_, i) {
          final item = items[i];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openingId == null ? () => _open(item) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: item.poster == null
                      ? const Center(child: Icon(Icons.movie_outlined, size: 38))
                      : CachedNetworkImage(
                          imageUrl: item.poster!, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined))),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${item.premiereYear ?? 'Year unknown'} · '
                            '${item.type == DiscoverType.series ? 'Series' : 'Movie'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11,
                                color: Colors.white60)),
                        const SizedBox(height: 4),
                        OriginLanguageLabel(
                          titleId: '',
                          tmdbId: item.tmdbId,
                          type: item.type == DiscoverType.series
                              ? 'series' : 'movie',
                          knownCountries: item.originCountries,
                          knownLanguage: item.originalLanguage,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_person?.name ?? widget.actorName)),
    body: _person == null
      ? FutureBuilder<List<TmdbPerson>>(
          future: _people,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load cast credits. Configure your TMDB key '
                  'in Discover and check your internet connection.',
                  textAlign: TextAlign.center),
              ));
            }
            final people = snapshot.data ?? const <TmdbPerson>[];
            if (people.isEmpty) return const Center(
              child: Text('No matching actor or actress found on TMDB.'));
            // Auto-select only when exactly one identity exists. Ambiguous
            // names require explicit user choice: never show wrong credits.
            if (people.length == 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _person == null) _select(people.single);
              });
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Padding(padding: EdgeInsets.all(12),
                  child: Text('Choose the person to see all their credited '
                      'movies and TV series.')),
                ...people.map(_personChoice),
              ],
            );
          },
        )
      : Column(children: [
          if (_openError != null) Padding(
              padding: const EdgeInsets.all(12), child: Text(
                _openError!, style: const TextStyle(color: Colors.orangeAccent))),
          Expanded(child: FutureBuilder<List<DiscoverTitle>>(
            future: _credits,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text(
                  'Credits unavailable. Try again later.'));
              }
              return _creditsGrid(snapshot.data ?? const []);
            },
          )),
        ]),
  );
}
