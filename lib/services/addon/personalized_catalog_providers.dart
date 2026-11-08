/// Opt-in iPad catalog providers using the standard Stremio addon protocol.
/// The user's provider account, watch history and AI configuration stay with
/// the third party. PlayTorrio only imports an explicitly supplied manifest.
enum PersonalizedCatalogProvider {
  xperience('Xperience', 'https://xperience-app.com/',
      'Curated presets and AI-generated catalog rows'),
  bingeCat('BingeCat', 'https://bingecat.com/',
      'Personalized catalogs based on your provider watch history');

  const PersonalizedCatalogProvider(this.label, this.setupUrl, this.description);
  final String label;
  final String setupUrl;
  final String description;
}

class PersonalizedCatalogManifest {
  const PersonalizedCatalogManifest._();

  /// We support token-bearing manifest path segments, not query manifests.
  /// Never log or include the submitted URL in an exception.
  static String normalize(String entered) {
    var input = entered.trim();
    if (input.startsWith('stremio://')) {
      input = 'https://' + input.substring('stremio://'.length);
    }
    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasQuery ||
        uri.pathSegments.isEmpty || uri.pathSegments.last != 'manifest.json') {
      throw const FormatException(
          'Paste the private HTTPS Stremio manifest.json link from the provider.');
    }
    return uri.toString();
  }
}
