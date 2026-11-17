/// Stremio manifest protocol models. Resource-specific capabilities and catalog
/// extras must survive persistence in private portable settings.
class AddonResource {
  final String name;

  /// Null means use the top-level types for a string-form resource.
  final List<String>? types;

  /// Null on an object-form resource means unrestricted identifiers.
  final List<String>? idPrefixes;

  final bool isObjectForm;

  const AddonResource({
    required this.name,
    this.types,
    this.idPrefixes,
    this.isObjectForm = false,
  });

  factory AddonResource.fromJson(dynamic value) {
    if (value is String) {
      final clean = value.trim();
      // Recover previously persisted Dart Map.toString() strings.
      if (clean.startsWith('{')) {
        final match = RegExp(r'name:\s*([a-z_]+)').firstMatch(clean);
        return AddonResource(name: match?.group(1) ?? '');
      }
      return AddonResource(name: clean);
    }
    if (value is Map) {
      return AddonResource(
        name: value['name']?.toString() ?? '',
        isObjectForm: true,
        types: value.containsKey('types')
            ? _parseStringList(value['types'])
            : null,
        // Per the SDK, an object without idPrefixes matches all IDs,
        // instead of inheriting the top-level restriction.
        idPrefixes: value.containsKey('idPrefixes')
            ? _parseStringList(value['idPrefixes'])
            : const [],
      );
    }
    return const AddonResource(name: '');
  }

  Map<String, dynamic> toJsonObject() => {
        'name': name,
        if (types != null) 'types': types,
        if (idPrefixes != null) 'idPrefixes': idPrefixes,
      };

  dynamic toJson() => isObjectForm ? toJsonObject() : name;
}

class AddonManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? logo;

  /// Kept for backwards compatibility with existing UI and settings.
  final List<String> resources;
  final List<String> types;
  final List<String> idPrefixes;
  final List<AddonCatalog> catalogs;

  /// Preserves the SDK's advanced resource descriptors across restarts/sync.
  final List<AddonResource> resourceDefinitions;

  AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.logo,
    required this.resources,
    required this.types,
    required this.idPrefixes,
    required this.catalogs,
    this.resourceDefinitions = const [],
  });

  bool supportsResource(String name) =>
      resources.contains(name) ||
      resourceDefinitions.any((resource) => resource.name == name);

  bool get supportsMeta => supportsResource('meta');
  bool get supportsCatalog => supportsResource('catalog');
  bool get supportsStream => supportsResource('stream');
  bool get supportsSubtitles => supportsResource('subtitles');

  /// Stremio filters *meta/stream/subtitles* by the resource's type and ID.
  /// Catalogs are enumerated separately; idPrefixes do not apply to them.
  bool supportsRequest(String resource, String type, String id) {
    if (!supportsResource(resource)) return false;

    final definitions =
        resourceDefinitions.where((entry) => entry.name == resource).toList();
    if (definitions.isEmpty) {
      return _matches(types, type) &&
          (resource == 'catalog' || _matchesPrefix(idPrefixes, id));
    }
    return definitions.any((entry) {
      final allowedTypes = entry.types ?? types;
      final allowedIds = entry.isObjectForm
          ? (entry.idPrefixes ?? const <String>[])
          : idPrefixes;
      return _matches(allowedTypes, type) &&
          (resource == 'catalog' || _matchesPrefix(allowedIds, id));
    });
  }

  static bool _matches(List<String> options, String value) =>
      options.isEmpty || options.contains(value);

  static bool _matchesPrefix(List<String> prefixes, String id) =>
      prefixes.isEmpty || prefixes.any(id.startsWith);

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    final descriptions = <AddonResource>[];
    if (json['resources'] is List) {
      for (final item in json['resources'] as List) {
        final resource = AddonResource.fromJson(item);
        if (resource.name.isNotEmpty) descriptions.add(resource);
      }
    }
    final catalogs = <AddonCatalog>[];
    if (json['catalogs'] is List) {
      for (final item in json['catalogs'] as List) {
        if (item is! Map) continue;
        try {
          final catalog = AddonCatalog.fromJson(Map<String, dynamic>.from(item));
          if (catalog.id.isNotEmpty && catalog.type.isNotEmpty) {
            catalogs.add(catalog);
          }
        } catch (_) {
          // Preserve other catalogs when a provider ships one malformed entry.
        }
      }
    }
    return AddonManifest(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Addon',
      version: json['version']?.toString() ?? '0.0.0',
      description: json['description']?.toString(),
      logo: json['logo']?.toString(),
      resources: descriptions.map((item) => item.name).toSet().toList(),
      resourceDefinitions: descriptions,
      types: _parseStringList(json['types']),
      idPrefixes: _parseStringList(json['idPrefixes']),
      catalogs: catalogs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        if (logo != null) 'logo': logo,
        'resources': resourceDefinitions.isNotEmpty
            ? resourceDefinitions.map((entry) => entry.toJson()).toList()
            : resources,
        'types': types,
        'idPrefixes': idPrefixes,
        'catalogs': catalogs.map((entry) => entry.toJson()).toList(),
      };
}

class AddonCatalogExtra {
  final String name;
  final bool isRequired;
  final List<String> options;
  final int? optionsLimit;

  const AddonCatalogExtra({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit,
  });

  factory AddonCatalogExtra.fromJson(dynamic value) {
    if (value is String) return AddonCatalogExtra(name: value);
    if (value is Map) {
      return AddonCatalogExtra(
        name: value['name']?.toString() ?? '',
        isRequired: value['isRequired'] == true,
        options: _parseStringList(value['options']),
        optionsLimit: value['optionsLimit'] is num
            ? (value['optionsLimit'] as num).toInt()
            : int.tryParse(value['optionsLimit']?.toString() ?? ''),
      );
    }
    return const AddonCatalogExtra(name: '');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (isRequired) 'isRequired': true,
        if (options.isNotEmpty) 'options': options,
        if (optionsLimit != null) 'optionsLimit': optionsLimit,
      };
}

class AddonCatalog {
  final String type;
  final String id;
  final String? name;
  final List<String> genres;
  final bool supportsSearch;
  final bool supportsSkip;
  final List<AddonCatalogExtra> extras;

  AddonCatalog({
    required this.type,
    required this.id,
    this.name,
    required this.genres,
    required this.supportsSearch,
    required this.supportsSkip,
    this.extras = const [],
  });

  bool supportsExtra(String name) =>
      extras.any((extra) => extra.name == name) ||
      (name == 'search' && supportsSearch) ||
      (name == 'skip' && supportsSkip) ||
      (name == 'genre' && genres.isNotEmpty);

  bool get hasRequiredExtras => extras.any((extra) => extra.isRequired);

  bool get isHomeEligible => !hasRequiredExtras;

  bool hasRequiredExtra(String name) =>
      extras.any((extra) => extra.name == name && extra.isRequired);

  factory AddonCatalog.fromJson(Map<String, dynamic> json) {
    final extras = <AddonCatalogExtra>[];
    // Legacy extraSupported names and current extra objects both matter.
    for (final key in ['extra', 'extraSupported']) {
      if (json[key] is! List) continue;
      for (final item in json[key] as List) {
        final extra = AddonCatalogExtra.fromJson(item);
        if (extra.name.isNotEmpty &&
            !extras.any((existing) => existing.name == extra.name)) {
          extras.add(extra);
        }
      }
    }

    // Older addons describe supported and required extras in separate
    // extraSupported/extraRequired string lists instead of modern objects.
    if (json['extraRequired'] is List) {
      for (final value in json['extraRequired'] as List) {
        final name = value?.toString() ?? '';
        if (name.isEmpty) continue;
        final index = extras.indexWhere((extra) => extra.name == name);
        if (index >= 0) {
          final previous = extras[index];
          extras[index] = AddonCatalogExtra(
            name: previous.name,
            isRequired: true,
            options: previous.options,
            optionsLimit: previous.optionsLimit,
          );
        } else {
          extras.add(AddonCatalogExtra(name: name, isRequired: true));
        }
      }
    }

    var genres = <String>[];
    final genreExtra = extras.where((extra) => extra.name == 'genre');
    if (genreExtra.isNotEmpty) genres = genreExtra.first.options;
    if (genres.isEmpty) genres = _parseStringList(json['genres']);

    return AddonCatalog(
      type: json['type']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      genres: genres,
      supportsSearch: json['supportsSearch'] == true ||
          extras.any((extra) => extra.name == 'search'),
      supportsSkip: json['supportsSkip'] == true ||
          extras.any((extra) => extra.name == 'skip'),
      extras: extras,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        if (name != null) 'name': name,
        'genres': genres,
        'supportsSearch': supportsSearch,
        'supportsSkip': supportsSkip,
        if (extras.isNotEmpty)
          'extra': extras.map((entry) => entry.toJson()).toList(),
      };
}

/// An addon that has been installed by the user.
class InstalledAddon {
  final String baseUrl;
  final AddonManifest manifest;
  bool enabled;
  bool enableCatalogs;
  bool enableSearch;
  bool enableSubtitles;
  bool enableStreams;

  /// True only when the user explicitly imports an iPad catalog trial.
  final bool personalizedCatalogTrial;

  InstalledAddon({
    required this.baseUrl,
    required this.manifest,
    this.enabled = true,
    this.enableCatalogs = true,
    this.enableSearch = true,
    this.enableSubtitles = true,
    this.enableStreams = true,
    this.personalizedCatalogTrial = false,
  });

  bool get isCatalogsActive =>
      enabled && enableCatalogs &&
      (manifest.supportsCatalog || manifest.catalogs.isNotEmpty);

  bool get isSearchActive => enabled && enableSearch &&
      manifest.catalogs.any((catalog) => catalog.supportsSearch);

  bool get isSubtitlesActive =>
      enabled && enableSubtitles && manifest.supportsSubtitles;

  bool get isStreamsActive =>
      enabled && enableStreams && manifest.supportsStream;

  factory InstalledAddon.fromJson(Map<String, dynamic> json) {
    return InstalledAddon(
      baseUrl: json['baseUrl']?.toString() ?? '',
      manifest: AddonManifest.fromJson(
          Map<String, dynamic>.from(json['manifest'] as Map)),
      enabled: json['enabled'] as bool? ?? true,
      enableCatalogs: json['enableCatalogs'] as bool? ?? true,
      enableSearch: json['enableSearch'] as bool? ?? true,
      enableSubtitles: json['enableSubtitles'] as bool? ?? true,
      enableStreams: json['enableStreams'] as bool? ?? true,
      personalizedCatalogTrial: json['personalizedCatalogTrial'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'manifest': manifest.toJson(),
        'enabled': enabled,
        'enableCatalogs': enableCatalogs,
        'enableSearch': enableSearch,
        'enableSubtitles': enableSubtitles,
        'enableStreams': enableStreams,
        if (personalizedCatalogTrial) 'personalizedCatalogTrial': true,
      };
}

List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return [];
}
