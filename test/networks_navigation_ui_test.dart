import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Networks has dedicated visible global dock entry and page', () {
    final dockSettings = File('lib/services/theme/dock_settings.dart')
        .readAsStringSync();
    final dock = File('lib/widgets/common/app_liquid_dock.dart')
        .readAsStringSync();
    final screen = File('lib/pages/networks/networks_page.dart')
        .readAsStringSync();
    expect(dockSettings, contains("key: 'networks'"));
    expect(dockSettings, contains("label: 'Networks'"));
    expect(dock, contains('case DockItemKey.networks:'));
    expect(dock, contains('const NetworksPage()'));
    expect(screen, contains('AppLiquidDock(currentDestination: DockItemKey.networks)'));
    expect(screen, contains('NetworkSource.streaming'));
    expect(screen, contains('NetworkSource.tvNetwork'));
    expect(screen, isNot(contains("name: 'Netflix'")),
        reason: 'Streaming services must come from TMDB, not hardcoded cards.');
    expect(screen, contains('Trending'));
    expect(screen, contains('Hot'));
    expect(screen, contains('Popular'));
    expect(screen, contains('All ('));
    expect(screen, contains('DetailsPage(movie: movie)'));
  });
}
