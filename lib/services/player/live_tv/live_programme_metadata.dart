/// Optional programme guide metadata attached to a Stremio live channel.
/// A TV channel name is NOT the title of the film/show currently broadcast.
class LiveProgrammeMetadata {
  const LiveProgrammeMetadata({this.title, this.kind});

  final String? title;
  final String? kind;

  static LiveProgrammeMetadata resolve({
    Map<String, dynamic>? metaHints,
    Map<String, dynamic>? streamHints,
  }) {
    String? pick(Object? value) {
      if (value is Map) {
        return pick(value['title'] ?? value['name'] ??
            value['programmeTitle'] ?? value['programTitle']);
      }
      if (value is! String) return null;
      final clean = value.trim();
      if (clean.isEmpty || clean.length > 300 ||
          clean.contains('://') || clean.contains('token=') ||
          clean.contains('apiKey=')) return null;
      return clean;
    }
    final all = <Map<String, dynamic>>[
      if (metaHints != null) metaHints,
      if (streamHints != null) streamHints,
    ];
    String? programmeTitle;
    String? kind;
    for (final hints in all) {
      programmeTitle ??= pick(hints['nowPlaying']) ??
          pick(hints['currentProgramme']) ??
          pick(hints['currentProgram']) ??
          pick(hints['programmeTitle']) ??
          pick(hints['programTitle']) ??
          pick(hints['epgTitle']) ??
          pick(hints['movieTitle']) ??
          pick(hints['showTitle']) ??
          pick(hints['epg']);
      kind ??= pick(hints['programmeType']) ??
          pick(hints['programType']) ?? pick(hints['contentType']);
    }
    return LiveProgrammeMetadata(title: programmeTitle, kind: kind);
  }
}
