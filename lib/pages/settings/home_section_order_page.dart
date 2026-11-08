import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/home/home_section_order_service.dart';

/// Drag the handle beside an individual Home row to change its priority.
/// Catalogs may be configured here even when currently offline or empty.
class HomeSectionOrderPage extends StatefulWidget {
  final List<MovieSection> currentSections;
  const HomeSectionOrderPage({
    super.key,
    this.currentSections = const <MovieSection>[],
  });

  @override
  State<HomeSectionOrderPage> createState() => _HomeSectionOrderPageState();
}

class _HomeSectionOrderPageState extends State<HomeSectionOrderPage> {
  late List<HomeSectionOrderChoice> _items;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _items = _choices();
  }

  List<HomeSectionOrderChoice> _choices() =>
      HomeSectionOrderService.choices(
        addons: AddonManager.instance.activeCatalogAddons,
        loaded: widget.currentSections,
      );

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    setState(() {
      final moved = _items.removeAt(oldIndex);
      _items.insert(newIndex, moved);
    });
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await HomeSectionOrderService.saveVisibleOrder(
        [for (final item in _items) item.id],
      );
    } catch (error) {
      debugPrint('[HomeOrder] Save failed (${error.runtimeType})');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save the new section order.'),
      ));
    }
  }

  Future<void> _reset() async {
    if (_resetting) return;
    setState(() => _resetting = true);
    try {
      await HomeSectionOrderService.reset();
      if (mounted) setState(() => _items = _choices());
    } catch (error) {
      debugPrint('[HomeOrder] Reset failed (${error.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not reset the section order.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        title: const Text('Arrange Home Sections'),
        actions: [
          TextButton.icon(
            onPressed: _resetting ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded, size: 20),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  'Drag the handles to arrange Xperience, TorBox Torrents, '
                  'Trakt recommendations and the other Home rows. '
                  'Changes are saved automatically. '
                  'Unavailable catalogs keep their place until they load.',
                  style: TextStyle(color: Colors.white70, height: 1.5),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  key: const ValueKey('home-section-order-list'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 30),
                  buildDefaultDragHandles: false,
                  itemCount: _items.length,
                  onReorder: _reorder,
                  proxyDecorator: (child, index, animation) => Material(
                    color: const Color(0xFF252337),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(14),
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final choice = _items[index];
                    return Card(
                      key: ValueKey(choice.id),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFF151822),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                        leading: CircleAvatar(
                          radius: 15,
                          backgroundColor: const Color(0xFF2E2946),
                          child: Text('${index + 1}',
                            style: const TextStyle(
                              color: Colors.white, fontSize: 12,
                              fontWeight: FontWeight.w700)),
                        ),
                        title: Text(choice.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: choice.subtitle.isEmpty
                          ? null
                          : Text(choice.subtitle, maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60)),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle_rounded,
                                color: Colors.white70),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
