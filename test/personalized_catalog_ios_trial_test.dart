import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/addon/addon_manager.dart';
import 'package:playtorrio/services/addon/personalized_catalog_providers.dart';
import 'package:playtorrio/services/metadata/metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('personalized catalog refresh is visible on Windows and iPad', () {
    final settingsSource =
        File('lib/pages/settings/addons_settings_page.dart').readAsStringSync();
    expect(settingsSource,
        contains('if (Platform.isIOS || Platform.isWindows) ...['));
    expect(
        RegExp(
          r'canRefresh:\s*\(Platform\.isIOS\s*\|\|\s*Platform\.isWindows\)\s*&&\s*addon\.personalizedCatalogTrial',
        ).hasMatch(settingsSource),
        isTrue,
        reason: 'Windows users must be able to reload provider catalog definitions.');
  });

  test('Xperience and BingeCat setup URLs are public, not private manifest URLs', () {
    expect(PersonalizedCatalogProvider.xperience.setupUrl,
        'https://xperience-app.com/');
    expect(PersonalizedCatalogProvider.bingeCat.setupUrl,
        'https://bingecat.com/');
  });

  test('catalog manifest import only accepts private-path HTTPS endpoints', () {
    expect(PersonalizedCatalogManifest.normalize(
        'stremio://xperience-app.com/private/manifest.json'),
        'https://xperience-app.com/private/manifest.json');
    expect(PersonalizedCatalogManifest.normalize(
        ' https://bingecat.com/account/manifest.json '),
        'https://bingecat.com/account/manifest.json');
    for (final url in <String>[
      'http://bingecat.com/private/manifest.json',
      'https://example.com/login',
      'https://alice:password@example.com/manifest.json',
      'https://example.com/manifest.json?token=secret',
      'https://example.com/manifest.json#fragment',
      'file:///data/manifest.json',
      'invalid',
    ]) {
      expect(() => PersonalizedCatalogManifest.normalize(url),
          throwsFormatException);
    }
  });

  test('personalized catalogs import, render, refresh and preserve existing addons',
      () async {
    SharedPreferences.setMockInitialValues({
      'installed_addons_v4': jsonEncode([
        {
          'baseUrl': 'https://v3-cinemeta.strem.io',
          'manifest': {
            'id': 'com.linvo.cinemeta', 'name': 'Cinemeta', 'version': '3.0.0',
            'resources': ['catalog'], 'types': ['movie'], 'idPrefixes': [],
            'catalogs': [
              {'type': 'movie', 'id': 'top', 'name': 'Trending'}
            ],
          },
          'enabled': true,
        },
      ]),
    });
    final manager=AddonManager.instance;
    var catalogVersion=1;
    var catalogRequests=0;
    MetadataService.manifestGetOverride=(uri) async {
      expect(uri.scheme,'https');
      expect(uri.pathSegments.last,'manifest.json');
      final isBinge=uri.host=='bingecat.com';
      return http.Response(jsonEncode({
        'id': isBinge ? 'trial.bingecat' : 'trial.xperience',
        'name': isBinge ? 'BingeCat Trial' : 'Xperience Trial',
        'version': '1.0.0',
        'resources': ['catalog','stream'],
        'types': ['movie','series'],
        'catalogs': [
          {'id':'picks','type':'movie','name':'Personalized picks'},
          if(catalogVersion>1) {'id':'series','type':'series','name':'New TV rows'},
        ],
      }),200);
    };
    MetadataService.catalogGetOverride=(uri) async {
      catalogRequests++;
      return http.Response(jsonEncode({'metas':[
        {'id':'tt0123456','name':'Sample title','type':'movie'},
      ]}),200);
    };
    try {
      await manager.initialize();
      expect(manager.addons.length,1);
      final xperience=await manager.addAddon(
        'https://xperience-app.com/demo/manifest.json',
        personalizedCatalogTrial:true,
      );
      expect(xperience.personalizedCatalogTrial,isTrue);
      expect(xperience.enableStreams,isFalse);
      expect(xperience.enableSearch,isFalse);
      expect(xperience.enableSubtitles,isFalse);
      expect(xperience.isCatalogsActive,isTrue);
      expect(xperience.manifest.catalogs.length,1);
      final bingecat=await manager.addAddon(
        'https://bingecat.com/demo/manifest.json',
        personalizedCatalogTrial:true,
      );
      expect(bingecat.manifest.id,'trial.bingecat');
      expect(manager.addons.length,3);
      expect(manager.addons.first.manifest.id,'com.linvo.cinemeta');
      await expectLater(manager.addAddon(
          'https://bingecat.com/demo/manifest.json',
          personalizedCatalogTrial:true),throwsException);

      final sections=await manager.fetchAllHomeSections();
      expect(sections.any((s)=>s.subtitle=='Xperience Trial'),isTrue);
      expect(sections.any((s)=>s.subtitle=='BingeCat Trial'),isTrue);
      final firstRequestCount=catalogRequests;
      await manager.fetchAllHomeSections();
      expect(catalogRequests,greaterThan(firstRequestCount),
          reason:'Personalized Home catalogs must bypass the in-memory cache.');

      await manager.updateAddonFeature(
          addonId:xperience.manifest.id,enableCatalogs:false);
      catalogVersion=2;
      final refreshed=await manager.refreshPersonalizedCatalog(
          xperience.manifest.id);
      expect(refreshed.manifest.catalogs.length,2);
      expect(refreshed.enableCatalogs,isFalse);
      expect(refreshed.enableStreams,isFalse);

      MetadataService.manifestGetOverride=(uri) async =>
          http.Response(jsonEncode({
            'id':'unexpected.provider', 'name':'Wrong', 'version':'1.0.0',
            'resources':['catalog'], 'types':['movie'],
            'catalogs':[{'id':'other','type':'movie'}],
          }),200);
      await expectLater(
          manager.refreshPersonalizedCatalog(xperience.manifest.id),
          throwsFormatException);
      final saved=manager.addons.firstWhere((a) =>
          a.manifest.id==xperience.manifest.id);
      expect(saved.manifest.catalogs.length,2);
      expect(saved.enableCatalogs,isFalse);
      expect(manager.addons.first.manifest.id,'com.linvo.cinemeta');
      await expectLater(manager.refreshPersonalizedCatalog('unknown'),
          throwsFormatException);
    } finally {
      MetadataService.manifestGetOverride=null;
      MetadataService.catalogGetOverride=null;
      MetadataService.clearCache();
    }
  });
}
