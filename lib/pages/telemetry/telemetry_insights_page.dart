import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/telemetry/telemetry_insights_repository.dart';
import '../../services/theme/dock_settings.dart';
import '../../widgets/common/app_liquid_dock.dart';

class TelemetryInsightsPage extends StatefulWidget {
  const TelemetryInsightsPage({super.key});
  @override
  State<TelemetryInsightsPage> createState() => _TelemetryInsightsPageState();
}

class _TelemetryInsightsPageState extends State<TelemetryInsightsPage> {
  static const _bg = Color(0xFF070D19);
  static const _panel = Color(0xFF121D30);
  static const _cyan = Color(0xFF37D7FF);
  static const _green = Color(0xFF52EBB9);
  static const _orange = Color(0xFFFFC16D);
  static const _purple = Color(0xFFB9A0FF);
  TelemetryInsightsData? _data;
  bool _loading = false;
  String? _error;
  String _range = '7';
  String _platform = 'all';
  int _generation = 0;

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _generation++; super.dispose(); }

  Future<void> _refresh() async {
    final serial = ++_generation;
    setState(() { _loading = true; _error = null; _data = null; });
    try {
      final result = await TelemetryInsightsRepository().load(
        days: _range == 'all' ? null : int.parse(_range),
        platform: _platform,
        isCancelled: () => !mounted || serial != _generation,
        onProgress: (data) {
          if (mounted && serial == _generation) setState(() => _data = data);
        },
      );
      if (mounted && serial == _generation) {
        setState(() { _data = result; _loading = false; });
      }
    } catch (e) {
      debugPrint('[Insights] Fetch failed: ' + e.runtimeType.toString());
      if (mounted && serial == _generation) {
        setState(() {
          _error = e is StateError ? e.message.toString() :
              'Private archive unavailable (' + e.runtimeType.toString() + ')';
          _loading = false;
        });
      }
    }
  }

  Widget _panelBox(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _cyan.withValues(alpha: 0.16)),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.20),
        blurRadius: 22, offset: const Offset(0, 8))],
    ),
    child: child,
  );

  Widget _filter(String label, String value, Map<String, String> options,
      ValueChanged<String> change) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label + '   ', style: const TextStyle(
          color: Colors.white54, fontSize: 10, letterSpacing: 1)),
      DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: value, dropdownColor: _panel,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        items: options.entries.map((e) => DropdownMenuItem<String>(
            value: e.key, child: Text(e.value))).toList(),
        onChanged: _loading ? null : (v) {
          if (v != null && v != value) { change(v); _refresh(); }
        },
      )),
    ]),
  );

  Widget _section(String heading, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 28, 0, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(heading, style: const TextStyle(fontSize: 17, color: Colors.white,
          fontWeight: FontWeight.w800, letterSpacing: 1.3)),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(
          fontSize: 12, color: Colors.white54)),
    ]),
  );

  Widget _metric(double width, String label, String value,
      String subtitle, Color accent, IconData icon) => SizedBox(
    width: width, child: _panelBox(Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: accent, size: 21),
        const SizedBox(height: 14),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(
            color: accent, fontSize: 29, fontWeight: FontWeight.w900))),
        const SizedBox(height: 7),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white,
            letterSpacing: 1, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
    ),
  );

  static List<double> _sample(List<double> points) {
    if (points.length <= 140) return List.of(points);
    return List.generate(140, (i) {
      final begin = (i * points.length / 140).floor();
      final end = math.min(points.length, ((i + 1) * points.length / 140).ceil());
      var sum = 0.0;
      for (var n = begin; n < end; n++) { sum += points[n]; }
      return sum / (end - begin);
    });
  }

  Widget _chart(double width, String label, String caption,
      List<double> data, Color color, String unit) {
    final points = _sample(data);
    final min = points.isEmpty ? 0.0 : points.reduce(math.min);
    final max = points.isEmpty ? 0.0 : points.reduce(math.max);
    return SizedBox(width: width, child: _panelBox(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
          Text(data.length.toString() + ' pts',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 5),
        Text(caption, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 18),
        SizedBox(height: 152, width: double.infinity,
            child: CustomPaint(painter: _TelemetryLinePainter(points, color))),
        const SizedBox(height: 11),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('MIN ' + min.toStringAsFixed(1) + unit,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(points.isEmpty ? 'NO SIGNAL' : 'HISTORICAL',
              style: TextStyle(color: color, fontSize: 10, letterSpacing: 1.2)),
          Text('MAX ' + max.toStringAsFixed(1) + unit,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    ));
  }

  Widget _bars(double width, String heading, Map<String, int> counts,
      TelemetryInsightsData data, Color accent) {
    final top = data.top(counts, limit: 9);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return SizedBox(width: width, child: _panelBox(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart_rounded, color: accent, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(heading, style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8))),
          Text(total.toString(), style: TextStyle(color: accent,
              fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 20),
        if (top.isEmpty) const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No observations', style: TextStyle(color: Colors.white54))),
        for (final entry in top) ...[
          Row(children: [
            Expanded(child: Text(entry.key, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11))),
            Text(entry.value.toString(), style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              minHeight: 5, backgroundColor: Colors.white10,
              value: total == 0 ? 0 : entry.value / total,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            )),
          const SizedBox(height: 13),
        ],
      ]),
    ));
  }

  Widget _devices(TelemetryInsightsData data) => _panelBox(Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.memory_rounded, color: _green),
        SizedBox(width: 10),
        Text('DEVICE INVENTORY', style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.bold, letterSpacing: 1)),
      ]),
      const SizedBox(height: 18),
      if (data.devices.isEmpty) const Text(
          'No hardware details in this selection.',
          style: TextStyle(color: Colors.white54)),
      for (final device in data.devices.entries) ...[
        Text(device.key.toUpperCase(), style:
            const TextStyle(color: _green, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        for (final field in device.value.entries) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 120, child: Text(field.key,
                style: const TextStyle(color: Colors.white54, fontSize: 12))),
            Expanded(child: Text(field.value,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
          ])),
        const Divider(color: Colors.white12),
      ],
      const SizedBox(height: 12),
      const Text('Serial numbers, MAC addresses, IPs and credentials are excluded.',
          style: TextStyle(color: Colors.white38, fontSize: 11)),
    ],
  ));

  Widget _insights(TelemetryInsightsData data) => _panelBox(Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.auto_awesome_rounded, color: _purple),
        SizedBox(width: 10),
        Text('ENGINEERING INSIGHTS', style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.bold, letterSpacing: 1)),
      ]),
      const SizedBox(height: 16),
      for (final item in data.insights) Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.circle, color: _purple, size: 7),
          const SizedBox(width: 10),
          Expanded(child: Text(item, style: const TextStyle(
              color: Colors.white70, height: 1.5, fontSize: 12))),
        ])),
    ],
  ));

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final available = MediaQuery.sizeOf(context).width;
    final w = math.min(1450.0, math.max(280.0, available - 36));
    final chartWidth = w > 900 ? (w - 16) / 2 : w;
    final metricWidth = w > 960 ? (w - 42) / 4 :
        w > 540 ? (w - 14) / 2 : w;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        const Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(
            center: Alignment(-0.7, -0.9), radius: 1.6,
            colors: [Color(0xFF142C41), _bg],
          )),
        )),
        SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 130),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1450),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70)),
                const Icon(Icons.satellite_alt_rounded, color: _cyan, size: 30),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MISSION CONTROL', style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w900, letterSpacing: 2.0,
                        fontSize: 22)),
                    Text('PLAYTORRIO  //  TELEMETRY INSIGHTS',
                        style: TextStyle(color: _cyan, letterSpacing: 1.8,
                            fontSize: 10)),
                  ],
                )),
                IconButton(tooltip: 'Refresh telemetry', onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded, color: _cyan)),
              ]),
              const SizedBox(height: 22),
              Wrap(spacing: 12, runSpacing: 10, children: [
                _filter('WINDOW', _range, const {
                  '1': '24 HOURS', '7': '7 DAYS',
                  '30': '30 DAYS', 'all': 'ALL HISTORY',
                }, (v) => setState(() => _range = v)),
                _filter('PLATFORM', _platform, const {
                  'all': 'ALL DEVICES', 'windows': 'WINDOWS', 'ios': 'IOS',
                }, (v) => setState(() => _platform = v)),
              ]),
              if (_loading) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(
                    value: data == null || data.discovered == 0 ? null :
                        (data.loaded + data.failed) / data.discovered,
                    backgroundColor: Colors.white10, color: _cyan),
                const SizedBox(height: 8),
                Text(data == null || data.discovered == 0
                    ? 'Scanning diagnostic folders…'
                    : 'Reading ' + (data.loaded + data.failed).toString() +
                        ' / ' + data.discovered.toString() + ' reports',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                _panelBox(Row(children: [
                  const Icon(Icons.error_outline, color: _orange),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error!,
                    style: const TextStyle(color: Colors.white70))),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ])),
              ],
              if (data != null) ...[
                const SizedBox(height: 18),
                Text('ARCHIVE COVERAGE  ·  ' + data.loaded.toString() +
                    ' LOADED / ' + data.discovered.toString() +
                    ' DISCOVERED / ' + data.failed.toString() + ' UNREADABLE',
                    style: const TextStyle(color: _green, letterSpacing: 0.7, fontSize: 11)),
                if (data.incomplete || data.warning != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(data.warning ?? 'Partial coverage: some reports were not read.',
                      style: const TextStyle(color: _orange, fontSize: 12))),
                _section('SYSTEM OVERVIEW', 'Private diagnostic uploads and observed playback health'),
                Wrap(spacing: 14, runSpacing: 14, children: [
                  _metric(metricWidth, 'REPORTS', data.loaded.toString(),
                      'Loaded diagnostic uploads', _cyan, Icons.cloud_done_rounded),
                  _metric(metricWidth, 'SAMPLES', data.sampleCount.toString(),
                      'Native playback observations', _green, Icons.monitor_heart_rounded),
                  _metric(metricWidth, 'BUFFERING', data.bufferingPercent.toStringAsFixed(1) + '%',
                      'Observed sample intervals', _orange, Icons.hourglass_bottom_rounded),
                  _metric(metricWidth, 'FRAME EVENTS',
                      (data.droppedFrames + data.decoderDrops + data.lateFrames).toString(),
                      'New drops and late frames', _purple, Icons.graphic_eq_rounded),
                  _metric(metricWidth, 'BUFFER WINDOW', data.averageCache.toStringAsFixed(1) + 's',
                      'Mean demuxer cache depth', _green, Icons.speed_rounded),
                  _metric(metricWidth, 'DECODED FPS', data.averageFps.toStringAsFixed(1),
                      'Mean video frames per second', _cyan, Icons.videocam_rounded),
                  _metric(metricWidth, 'A/V DRIFT', data.averageSyncMs.toStringAsFixed(1) + 'ms',
                      'Mean absolute sync offset', _purple, Icons.sync_rounded),
                  _metric(metricWidth, 'SOURCE TRACES', data.sourceEvents.toString(),
                      'Observed provider events', _orange, Icons.hub_rounded),
                ]),
                _section('SIGNAL ANALYTICS', 'Chronological telemetry trends from actual reports'),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  _chart(chartWidth, 'UPLOAD ACTIVITY', 'Daily reports',
                      data.dailyReports.values.map((e) => e.toDouble()).toList(), _cyan, ''),
                  _chart(chartWidth, 'FAILURE ACTIVITY', 'Daily failure-related uploads',
                      data.dailyReports.keys.map((k) =>
                          (data.dailyFailures[k] ?? 0).toDouble()).toList(), _orange, ''),
                  _chart(chartWidth, 'BUFFER DEPTH', 'Demuxer cache seconds',
                      data.cacheTrend, _green, 's'),
                  _chart(chartWidth, 'VIDEO FRAME RATE', 'Decoder FPS',
                      data.fpsTrend, _cyan, 'fps'),
                  _chart(chartWidth, 'FRAME LOSS', 'New drops and late frames per sample',
                      data.dropTrend, _orange, ''),
                  _chart(chartWidth, 'A/V SYNC', 'Absolute synchronization error',
                      data.syncTrend, _purple, 'ms'),
                ]),
                _section('OPERATIONS AND PROVIDERS', 'Frequency and distribution of observed events'),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  _bars(chartWidth, 'EVENT CODES', data.events, data, _cyan),
                  _bars(chartWidth, 'REPORT REASONS', data.reasons, data, _orange),
                  _bars(chartWidth, 'SOURCE PROVIDERS', data.sources, data, _purple),
                  _bars(chartWidth, 'RESOLUTION SIGNALS', data.resolutions, data, _green),
                  _bars(chartWidth, 'MEDIA TITLES', data.titles, data, _cyan),
                  _bars(chartWidth, 'APP BUILDS', data.builds, data, _orange),
                  _bars(chartWidth, 'DEVICE PLATFORMS', data.platforms, data, _green),
                  _bars(chartWidth, 'NATIVE AUDIO CODECS', data.codecs, data, _purple),
                ]),
                _section('HARDWARE AND ENGINEERING', 'Device capabilities and evidence-based diagnostics'),
                _devices(data),
                const SizedBox(height: 16),
                _insights(data),
                const SizedBox(height: 24),
                const Text('PRIVATE GITHUB TELEMETRY · READ ONLY · NO SYNTHETIC METRICS',
                  style: TextStyle(color: Colors.white38, fontSize: 10,
                      letterSpacing: 1.2)),
              ],
            ]),
          )),
        )),
        Positioned(
          left: 0, right: 0, bottom: 12 + MediaQuery.paddingOf(context).bottom,
          child: const Center(child: AppLiquidDock(
              currentDestination: DockItemKey.telemetry)),
        ),
      ]),
    );
  }
}

class _TelemetryLinePainter extends CustomPainter {
  _TelemetryLinePainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF2A4057)..strokeWidth = 0.7;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i <= 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    if (points.isEmpty) return;
    final lower = points.reduce(math.min);
    final upper = points.reduce(math.max);
    final span = math.max(0.001, upper - lower);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1 ? size.width / 2 :
          i * size.width / (points.length - 1);
      final y = size.height - 9 - (points[i] - lower) *
          (size.height - 18) / span;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    final shade = Path.from(path)
      ..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(shade, Paint()..shader = LinearGradient(
      colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.01)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
    ).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 2
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _TelemetryLinePainter oldDelegate) => true;
}
