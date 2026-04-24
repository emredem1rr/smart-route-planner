import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/models/route_result_model.dart';
import '../../core/services/pdf_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/settings_provider.dart';

class RouteResultScreen extends StatefulWidget {
  final OptimizeResponse response;
  const RouteResultScreen({super.key, required this.response});

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen>
    with SingleTickerProviderStateMixin {
  late TabController   _tabController;
  late List<dynamic>   _orderedTasks;   // drag & drop için kopyası
  // Navigasyon
  final _navService  = NavigationService();
  StreamSubscription<NavState>? _navSub;
  NavState? _navState;
  bool      _navActive = false;
  late Set<String>     _selectedAlgos;  // grafik filtresi

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _orderedTasks  = List.from(widget.response.result!.orderedTasks);
    _selectedAlgos = widget.response.comparisonLogs
        .map((l) => l.algorithm).toSet();
    // Rota geçmişine kaydet
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveHistory());
  }

  void _startNavigation() {
    final tasks = _orderedTasks.cast<dynamic>().toList();
    setState(() { _navActive = true; });
    _navSub = _navService.start(
      tasks.map((t) => t as dynamic).toList().cast(),
    ).listen((state) {
      setState(() => _navState = state);
      if (state.completed) {
        setState(() => _navActive = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('🎉 Tüm görevler tamamlandı!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      }
    });
  }

  void _stopNavigation() {
    _navSub?.cancel();
    _navService.stop();
    setState(() { _navActive = false; _navState = null; });
  }

  Future<void> _saveHistory() async {
    final sonuc = widget.response.result;
    if (sonuc == null) return;
    try {
      final token = await StorageService().getToken();
      final now   = DateTime.now();
      final now2  = DateTime.now();
      final date  = '${now2.year}-${now2.month.toString().padLeft(2, '0')}-${now2.day.toString().padLeft(2, '0')}';
      final names = sonuc.orderedTasks.map((t) => t.name).join(', ');
      await http.post(
        Uri.parse('\${ApiConstants.baseUrl}/routes/history'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer \$token',
        },
        body: jsonEncode({
          'task_date':         date,
          'total_distance':    sonuc.totalDistance,
          'total_travel_time': sonuc.totalTravelTime,
          'algorithm_used':    sonuc.algorithmUsed,
          'fitness_score':     sonuc.fitnessScore,
          'execution_time_ms': sonuc.executionTimeMs,
          'task_names':        names,
          'task_count':        sonuc.orderedTasks.length,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _navService.stop();
    _tabController.dispose();
    super.dispose();
  }

  // İki görev arasındaki seyahat süresini hesapla (dist_matrix yok ama
  // toplam süreyi n'e bölerek ortalama verebiliriz)
  String _travelTime(int fromIdx) {
    final sonuc = widget.response.result!;
    if (sonuc.orderedTasks.isEmpty) return '';
    final avgMin = sonuc.totalTravelTime / (sonuc.orderedTasks.length + 1);
    return '~${avgMin.toStringAsFixed(0)} dk yol';
  }

  @override
  Widget build(BuildContext context) {
    final sonuc  = widget.response.result!;
    final t      = context.watch<SettingsProvider>().t;
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor:  surf,
        elevation:        0,
        toolbarHeight:    64,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: AppColors.surfaceHigh(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border)),
              child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
            ),
          ),
        ),
        title: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.route_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text(
            t('route_result'),
            style: TextStyle(color: tp, fontSize: 16, fontWeight: FontWeight.w700,
                letterSpacing: -0.3),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: sonuc.usedRealRoads
                  ? AppColors.success.withOpacity(0.12)
                  : AppColors.textSecond(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: sonuc.usedRealRoads
                    ? AppColors.success.withOpacity(0.4)
                    : AppColors.border(context),
              ),
            ),
            child: Text(
              sonuc.usedRealRoads ? '🛣️ Gerçek Yol' : '📐 Kuş Uçuşu',
              style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.w600,
                color: sonuc.usedRealRoads
                    ? AppColors.success
                    : AppColors.textSecond(context),
              ),
            ),
          ),
        ]),
        actions: [
          // Paylaş dropdown
          PopupMenuButton<String>(
            icon:    Icon(Icons.share_outlined, color: tp),
            tooltip: 'Paylaş',
            shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              switch (v) {
                case 'share':    _shareRoute(sonuc); break;
                case 'whatsapp': _shareWhatsApp(sonuc); break;
                case 'maps':     _openNavigation(sonuc); break;
                case 'copy':     _copyToClipboard(sonuc); break;
              }
            },
            itemBuilder: (_) => [
              _popItem('share',    Icons.share_outlined,   tp,                        'Paylaş'),
              _popItem('whatsapp', Icons.chat_outlined,    const Color(0xFF25D366),   'WhatsApp'),
              _popItem('maps',     Icons.map_outlined,     const Color(0xFF4285F4),   'Google Maps'),
              _popItem('copy',     Icons.copy_outlined,    tp,                        'Panoya Kopyala'),
            ],
          ),
          IconButton(
            icon:      Icon(Icons.picture_as_pdf_outlined, color: tp),
            tooltip:   'PDF Raporu',
            onPressed: () async {
              await PdfService().generateRouteReport(widget.response);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            Divider(height: 1, color: border),
            TabBar(
              controller:           _tabController,
              indicatorColor:       AppColors.orange,
              indicatorWeight:      2.5,
              labelColor:           AppColors.orange,
              unselectedLabelColor: ts,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(icon: Icon(Icons.map_outlined,      size: 18), text: 'Harita'),
                Tab(icon: Icon(Icons.list_outlined,     size: 18), text: 'Sıra'),
                Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'Karşılaştırma'),
              ],
            ),
          ]),
        ),
      ),
      body: Column(children: [
        // ── Navigasyon banner ──────────────────────────────
        if (_navActive && _navState != null && !_navState!.completed)
          _NavBanner(state: _navState!, onStop: _stopNavigation),
        Expanded(child: TabBarView(
          controller: _tabController,
          children: [
            _buildMapTab(sonuc),
            _buildListTab(sonuc),
            _buildComparisonTab(widget.response.comparisonLogs, sonuc),
          ],
        )),
      ]),
    );
  }

  // ── Paylaşım ───────────────────────────────────────────────

  String _buildShareText(RouteResult sonuc) {
    const sep = '━━━━━━━━━━━━━━';
    final nums = ['1️⃣','2️⃣','3️⃣','4️⃣','5️⃣','6️⃣','7️⃣','8️⃣','9️⃣','🔟'];
    final b   = StringBuffer('📍 Bugünkü Rotam\n$sep\n');
    final now = DateTime.now();
    int cumMin = now.hour * 60 + now.minute;

    for (int i = 0; i < _orderedTasks.length; i++) {
      final task   = _orderedTasks[i];
      final segMin = (sonuc.segmentTimes != null && i < sonuc.segmentTimes!.length)
          ? sonuc.segmentTimes![i].round() : 0;
      cumMin += segMin;
      final h  = (cumMin ~/ 60 % 24).toString().padLeft(2, '0');
      final m  = (cumMin % 60).toString().padLeft(2, '0');
      final em = i < nums.length ? nums[i] : '${i+1}.';
      b.writeln('$em ${task.name} — $h:$m');
      if (task.address.isNotEmpty) {
        b.writeln('   📌 ${task.address} | ⏱ ${task.duration} dk');
      } else {
        b.writeln('   ⏱ ${task.duration} dk');
      }
      b.writeln(sep);
    }

    b.writeln('📊 Toplam: ${sonuc.totalDistance.toStringAsFixed(1)} km | ${sonuc.totalTravelTime.round()} dakika');
    b.writeln('🤖 Smart Route Planner ile optimize edildi');
    return b.toString();
  }

  void _shareRoute(RouteResult sonuc) {
    final text = _buildShareText(sonuc);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Rotayı Paylaş',
                style: TextStyle(color: AppColors.textPrimary(context),
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _shareOptionBtn(Icons.chat_rounded,   'WhatsApp',
                  const Color(0xFF25D366),
                      () { Navigator.pop(context); _shareWhatsApp(sonuc); }),
              _shareOptionBtn(Icons.sms_rounded,    'SMS',
                  const Color(0xFF34C759),
                      () { Navigator.pop(context); _shareSMS(text); }),
              _shareOptionBtn(Icons.share_rounded,  'Diğer',
                  AppColors.info,
                      () { Navigator.pop(context);
                  Share.share(text, subject: 'Smart Route Planım'); }),
              _shareOptionBtn(Icons.copy_rounded,   'Kopyala',
                  AppColors.orange,
                      () { Navigator.pop(context); _copyToClipboard(sonuc); }),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _shareOptionBtn(IconData icon, String label,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12), shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(
            color: AppColors.textSecond(context),
            fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Future<void> _shareSMS(String text) async {
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      Share.share(text);
    }
  }

  void _shareWhatsApp(RouteResult sonuc) async {
    final encoded = Uri.encodeComponent(_buildShareText(sonuc));
    final uri     = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _shareRoute(sonuc); // WhatsApp yoksa genel paylaş
    }
  }

  void _copyToClipboard(RouteResult sonuc) {
    Clipboard.setData(ClipboardData(text: _buildShareText(sonuc)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         const Text('Rota panoya kopyalandı.'),
      backgroundColor: AppColors.success,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  PopupMenuItem<String> _popItem(
      String value, IconData icon, Color color, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
            color: AppColors.textPrimary(context), fontSize: 14)),
      ]),
    );
  }

  // ── Tab 1: Harita ──────────────────────────────────────────
  Widget _buildMapTab(RouteResult sonuc) {
    final markers        = <Marker>[];
    final waypointPoints = <LatLng>[];

    final startLoc = widget.response.startLocation;
    if (startLoc != null) {
      final p = LatLng(startLoc['latitude']!, startLoc['longitude']!);
      waypointPoints.add(p);
      markers.add(Marker(point: p, width: 44, height: 44, child: _startMarker()));
    }

    for (int i = 0; i < _orderedTasks.length; i++) {
      final task = _orderedTasks[i];
      final p    = LatLng(task.latitude, task.longitude);
      waypointPoints.add(p);
      markers.add(Marker(
        point: p, width: 44, height: 44,
        child: _mapMarker(i + 1, task.priority),
      ));
    }

    // Gerçek yol geometrisi varsa kullan, yoksa düz çizgi
    final polyPoints = sonuc.routeGeometry != null
        ? sonuc.routeGeometry!.map((p) => LatLng(p[0], p[1])).toList()
        : waypointPoints;

    final allLats   = waypointPoints.map((p) => p.latitude).toList();
    final allLons   = waypointPoints.map((p) => p.longitude).toList();
    final centerLat = allLats.isNotEmpty
        ? allLats.reduce((a, b) => a + b) / allLats.length : 40.6499;
    final centerLon = allLons.isNotEmpty
        ? allLons.reduce((a, b) => a + b) / allLons.length : 35.8353;

    return Column(children: [
      _summaryBar(sonuc),
      Expanded(
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(centerLat, centerLon),
              initialZoom:   13,
            ),
            children: [
              TileLayer(
                urlTemplate:          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smartroute.app',
              ),
              if (polyPoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points:      polyPoints,
                    color:       AppColors.orange,
                    strokeWidth: sonuc.usedRealRoads ? 4.5 : 3.0,
                    isDotted:    !sonuc.usedRealRoads,
                  ),
                ]),
              MarkerLayer(markers: markers),
            ],
          ),
          // Sağ üst: gerçek yol bilgisi
          Positioned(
            top: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:        AppColors.surface(context).withOpacity(0.92),
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppColors.border(context)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.1), blurRadius: 6,
                  offset: const Offset(0, 2),
                )],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  sonuc.usedRealRoads
                      ? Icons.route_rounded
                      : Icons.straighten_rounded,
                  size:  14,
                  color: sonuc.usedRealRoads
                      ? AppColors.success
                      : AppColors.textSecond(context),
                ),
                const SizedBox(width: 5),
                Text(
                  sonuc.usedRealRoads ? 'Gerçek Yol' : 'Kuş Uçuşu',
                  style: TextStyle(
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                    color: sonuc.usedRealRoads
                        ? AppColors.success
                        : AppColors.textSecond(context),
                  ),
                ),
              ]),
            ),
          ),
          // Alt: butonlar
          Positioned(
            bottom: 16, left: 16,
            child: FloatingActionButton.extended(
              heroTag:         'live_nav',
              onPressed:       _navActive ? _stopNavigation : _startNavigation,
              icon:            Icon(_navActive ? Icons.stop_rounded : Icons.near_me_rounded),
              label:           Text(_navActive ? 'Durdur' : 'Canlı Takip'),
              backgroundColor: _navActive ? AppColors.danger : AppColors.success,
              foregroundColor: Colors.white,
              elevation:       2,
            ),
          ),
          Positioned(
            bottom: 16, right: 16,
            child: FloatingActionButton.extended(
              heroTag:         'directions',
              onPressed:       () => _openNavigation(sonuc),
              icon:            const Icon(Icons.navigation_rounded),
              label:           const Text('Yol Tarifi'),
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              elevation:       2,
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _summaryBar(RouteResult sonuc) {
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Container(
      color:   surf,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _summaryItem('${sonuc.totalDistance.toStringAsFixed(2)} km',
                'Mesafe', Icons.straighten_outlined, tp, ts),
            _dividerV(border),
            _summaryItem('${sonuc.totalTravelTime.toStringAsFixed(0)} dk',
                'Süre', Icons.timer_outlined, tp, ts),
            _dividerV(border),
            _summaryItem(sonuc.fitnessScore.toStringAsFixed(4),
                'Fitness', Icons.speed_outlined, tp, ts),
            _dividerV(border),
            _summaryItem(_algoLabel(sonuc.algorithmUsed),
                'Algoritma', Icons.psychology_outlined, tp, ts),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (sonuc.trafficUsed)
            _infoBadge('🚦 Trafik verisi aktif', AppColors.success)
          else if (sonuc.usedRealRoads)
            _infoBadge('🗺️ Gerçek yol verisi', AppColors.info)
          else
            _infoBadge('📐 Tahmini mesafe', ts),
        ]),
        const SizedBox(height: 6),
        Divider(height: 1, color: border),
      ]),
    );
  }

  Widget _infoBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _dividerV(Color border) =>
      Container(width: 1, height: 32, color: border);

  Widget _summaryItem(
      String value, String label, IconData icon, Color tp, Color ts) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppColors.orange, size: 16),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              color: tp, fontWeight: FontWeight.w700, fontSize: 12)),
      Text(label, style: TextStyle(color: ts, fontSize: 10)),
    ]);
  }

  Widget _mapMarker(int order, int priority) {
    return Container(
      decoration: BoxDecoration(
        color:  _priorityColor(priority),
        shape:  BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.25), blurRadius: 4,
          offset: const Offset(0, 2),
        )],
      ),
      child: Center(child: Text('$order',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
    );
  }

  Widget _startMarker() {
    return Container(
      decoration: BoxDecoration(
        color:  AppColors.success,
        shape:  BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.25), blurRadius: 4,
          offset: const Offset(0, 2),
        )],
      ),
      child: const Center(
          child: Icon(Icons.my_location, color: Colors.white, size: 20)),
    );
  }

  // ── Tab 2: Liste ───────────────────────────────────────────
  Widget _buildListTab(RouteResult sonuc) {
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _summaryCard(sonuc, surf, border, tp, ts),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7C3AED).withOpacity(0.10),
                    const Color(0xFF6366F1).withOpacity(0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF7C3AED).withOpacity(0.30)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Color(0xFF7C3AED), size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✨ Yapay Zekâ Analizi',
                          style: TextStyle(
                            color: Color(0xFF7C3AED),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 4),
                      Text(
                        sonuc.aiExplanation != null && sonuc.aiExplanation!.isNotEmpty
                            ? sonuc.aiExplanation!
                            : '${sonuc.orderedTasks.length} görev ${sonuc.totalDistance.toStringAsFixed(1)} km mesafe ve yaklaşık ${sonuc.totalTravelTime.round()} dakika seyahat süresiyle optimize edildi. ${_algoLabel(sonuc.algorithmUsed)} algoritması kullanılarak en verimli rota sırası belirlendi.',
                        style: TextStyle(color: tp, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (sonuc.improvementPercent != null && sonuc.improvementPercent! > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.bar_chart_rounded, color: AppColors.success, size: 16),
                    SizedBox(width: 6),
                    Text('📊 Optimizasyon Etkisi',
                        style: TextStyle(color: AppColors.success,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Manuel plana göre %${sonuc.improvementPercent!.toStringAsFixed(1)} daha kısa rota',
                    style: TextStyle(color: tp, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Yaklaşık ${sonuc.kmSaved!.toStringAsFixed(1)} km ve ${sonuc.minutesSaved!.toStringAsFixed(0)} dakika tasarruf',
                    style: TextStyle(color: ts, fontSize: 12),
                  ),
                ]),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Icon(Icons.drag_indicator, size: 14,
                  color: AppColors.textDim(context)),
              const SizedBox(width: 4),
              Text('Sırayı değiştirmek için basılı tut',
                  style: TextStyle(fontSize: 11,
                      color: AppColors.textSecond(context))),
            ]),
          ),
        ),
        SliverReorderableList(
          itemCount:    _orderedTasks.length,
          onReorder: (oldIdx, newIdx) {
            setState(() {
              if (newIdx > oldIdx) newIdx--;
              final item = _orderedTasks.removeAt(oldIdx);
              _orderedTasks.insert(newIdx, item);
            });
          },
          itemBuilder: (_, i) {
            final task = _orderedTasks[i];
            return ReorderableDragStartListener(
              key:   ValueKey(task.id),
              index: i,
              child: _taskCard(
                i + 1, task, surf, border, tp, ts,
                travelTime: i == 0
                    ? null
                    : _travelTimeBetween(i - 1, i, sonuc),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  String? _travelTimeBetween(int fromIdx, int toIdx, RouteResult sonuc) {
    // segment_times: index 0 = başlangıç→1.durak, 1 = 1.durak→2.durak, ...
    final segs = sonuc.segmentTimes;
    if (segs != null && toIdx < segs.length) {
      final min = segs[toIdx];
      if (min < 1) return '< 1 dk yol';
      return '${min.toStringAsFixed(0)} dk yol';
    }
    // Fallback: mesafeye göre tahmin
    if (sonuc.totalTravelTime > 0 && sonuc.orderedTasks.isNotEmpty) {
      final avg = sonuc.totalTravelTime / sonuc.orderedTasks.length;
      return '≈ ${avg.toStringAsFixed(0)} dk yol';
    }
    return null;
  }

  Widget _summaryCard(RouteResult sonuc,
      Color surf, Color border, Color tp, Color ts) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:        AppColors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_algoLabel(sonuc.algorithmUsed),
                style: const TextStyle(
                    color: AppColors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: sonuc.usedRealRoads
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.textSecond(context).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sonuc.usedRealRoads ? '🛣️ Gerçek Yol' : '📐 Kuş Uçuşu',
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w600,
                color: sonuc.usedRealRoads
                    ? AppColors.success
                    : AppColors.textSecond(context),
              ),
            ),
          ),
          const Spacer(),
          Text('${sonuc.executionTimeMs.toStringAsFixed(0)} ms',
              style: TextStyle(color: ts, fontSize: 12)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _statBox('${sonuc.totalDistance.toStringAsFixed(2)} km',
              'Mesafe', const Color(0xFF3D9CF5), surf, border, tp, ts)),
          const SizedBox(width: 10),
          Expanded(child: _statBox('${sonuc.totalTravelTime.toStringAsFixed(0)} dk',
              'Süre', AppColors.success, surf, border, tp, ts)),
          const SizedBox(width: 10),
          Expanded(child: _statBox(sonuc.fitnessScore.toStringAsFixed(3),
              'Fitness', AppColors.warn, surf, border, tp, ts)),
        ]),
        const SizedBox(height: 12),
        Divider(color: border),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.info_outline, size: 14, color: ts),
          const SizedBox(width: 6),
          Text(
            'Sezgisel: ${sonuc.heuristicUsed == 'euclidean' ? 'Öklid' : 'Manhattan'}',
            style: TextStyle(color: ts, fontSize: 12),
          ),
        ]),
      ]),
    );
  }

  Widget _statBox(String value, String label, Color accent,
      Color surf, Color border, Color tp, Color ts) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color:        accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                color: accent, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: ts, fontSize: 11)),
      ]),
    );
  }

  Widget _taskCard(int order, dynamic task,
      Color surf, Color border, Color tp, Color ts,
      {String? travelTime}) {
    final prioColor = _priorityColor(task.priority);

    return Column(
      key: ValueKey(task.id),
      children: [
        // Seyahat süresi göstergesi (1. kart hariç)
        if (travelTime != null)
          Padding(
            padding: const EdgeInsets.only(left: 18, bottom: 2),
            child: Row(children: [
              Container(
                width: 1.5, height: 20,
                color: AppColors.border(context),
              ),
              const SizedBox(width: 8),
              Icon(Icons.directions_car, size: 12,
                  color: AppColors.textDim(context)),
              const SizedBox(width: 4),
              Text(travelTime,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textDim(context))),
            ]),
          ),
        // Kart
        Container(
          margin:  const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color:        surf,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: border),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openInMaps(task),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color:  prioColor.withOpacity(0.12),
                      shape:  BoxShape.circle,
                      border: Border.all(color: prioColor.withOpacity(0.4)),
                    ),
                    child: Center(child: Text('$order',
                        style: TextStyle(
                            color: prioColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(task.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14, color: tp)),
                          if (task.address.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(task.address,
                                style: TextStyle(color: ts, fontSize: 12),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    // Hizmet süresi (kullanıcının girdiği süre)
                    const SizedBox(height: 2),
                    // Yol tarifi ikonu
                    Icon(Icons.open_in_new,
                        color: AppColors.textDim(context), size: 16),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openInMaps(dynamic task) async {
    final lat = task.latitude;
    final lng = task.longitude;
    final name = Uri.encodeComponent(task.name);
    // Google Maps yol tarifi URL'i
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$name&travelmode=driving',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ── Tab 3: Karşılaştırma ───────────────────────────────────
  Widget _buildComparisonTab(List<AlgorithmLog> loglar, RouteResult sonuc) {
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Algoritma Karşılaştırması',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tp)),
        const SizedBox(height: 4),
        Text('Tüm algoritmalar aynı görevler üzerinde test edildi',
            style: TextStyle(fontSize: 13, color: ts)),
        const SizedBox(height: 16),

        // Algoritma kartları
        ...loglar.map((log) {
          final kazanan = log.algorithm == sonuc.algorithmUsed;
          final color   = _algoColor(log.algorithm);
          return Container(
            margin:  const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        kazanan ? color.withOpacity(0.07) : surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: kazanan ? color : border,
                  width: kazanan ? 1.5 : 1),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color:        color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_algoIcon(log.algorithm), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(log.label,
                        style: TextStyle(fontWeight: FontWeight.w600,
                            fontSize: 14, color: tp)),
                    if (kazanan) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('✓ Kazanan',
                            style: TextStyle(color: AppColors.success,
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Fitness: ${log.fitnessScore.toStringAsFixed(4)}  ·  '
                        '${log.totalDistance.toStringAsFixed(2)} km  ·  '
                        '${log.executionTimeMs.toStringAsFixed(1)} ms',
                    style: TextStyle(fontSize: 12, color: ts),
                  ),
                ]),
              ),
            ]),
          );
        }),

        // Fitness grafiği
        if (loglar.any((l) => l.fitnessHistory.isNotEmpty)) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fitness Gelişimi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tp)),
              Text('Filtrele:', style: TextStyle(fontSize: 12, color: ts)),
            ],
          ),
          const SizedBox(height: 10),

          // Tıklanabilir legend — benchmark gibi
          Wrap(
            spacing: 8, runSpacing: 8,
            children: loglar.where((l) => l.fitnessHistory.isNotEmpty).map((log) {
              final selected = _selectedAlgos.contains(log.algorithm);
              final color    = _algoColor(log.algorithm);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected && _selectedAlgos.length > 1) {
                    _selectedAlgos.remove(log.algorithm);
                  } else {
                    _selectedAlgos.add(log.algorithm);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:        selected ? color.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border:       Border.all(
                        color: selected ? color : AppColors.border(context),
                        width: selected ? 1.5 : 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color:  selected ? color : Colors.transparent,
                        shape:  BoxShape.circle,
                        border: Border.all(color: color),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(log.label,
                        style: TextStyle(
                          fontSize:   12,
                          color:      selected ? color : ts,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Grafik
          Container(
            height:  240,
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            decoration: BoxDecoration(
              color:        surf,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: border),
            ),
            child: _buildFitnessChart(
                loglar.where((l) => _selectedAlgos.contains(l.algorithm)).toList()),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFitnessChart(List<AlgorithmLog> loglar) {
    final ts    = AppColors.textSecond(context);
    final lines = loglar.where((l) => l.fitnessHistory.isNotEmpty).map((log) {
      final spots = log.fitnessHistory
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList();
      return LineChartBarData(
        spots:        spots,
        isCurved:     true,
        color:        _algoColor(log.algorithm),
        barWidth:     2,
        dotData:      const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    // Y ekseni dinamik aralık — küçük değişiklikler görünsün
    final allValues = loglar
        .where((l) => l.fitnessHistory.isNotEmpty)
        .expand((l) => l.fitnessHistory)
        .toList();
    double minY = allValues.isEmpty ? 0 : allValues.reduce((a, b) => a < b ? a : b);
    double maxY = allValues.isEmpty ? 1 : allValues.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    // Çok küçük aralıkta bile göster
    if (range < 0.01) {
      minY -= 0.05;
      maxY += 0.05;
    } else {
      minY -= range * 0.05;
      maxY += range * 0.05;
    }

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      lineBarsData: lines,
      gridData: FlGridData(
        show: true,
        horizontalInterval: range < 0.01 ? 0.01 : null,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: AppColors.border(context), strokeWidth: 0.6),
        getDrawingVerticalLine: (_) =>
            FlLine(color: AppColors.border(context), strokeWidth: 0.6),
      ),
      borderData: FlBorderData(
          show:   true,
          border: Border.all(color: AppColors.border(context))),
      clipData: const FlClipData.all(),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles:   true,
            reservedSize: 56,
            getTitlesWidget: (v, _) => Text(
              v.toStringAsFixed(range < 0.1 ? 4 : 3),
              style: TextStyle(fontSize: 8, color: ts),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) => Text(
              '${v.toInt()}',
              style: TextStyle(fontSize: 8, color: ts),
            ),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
    ));
  }

  // ── Navigation ─────────────────────────────────────────────
  Future<void> _openNavigation(RouteResult sonuc) async {
    if (sonuc.orderedTasks.isEmpty) return;
    final tasks = _orderedTasks;
    final dest  = tasks.last;

    final waypointStr = tasks.length > 1
        ? tasks.sublist(0, tasks.length - 1)
            .map((t) => '${t.latitude},${t.longitude}')
            .join('%7C')
        : '';

    // Web URL (Android + iOS fallback)
    final webUrl = tasks.length == 1
        ? 'https://www.google.com/maps/dir/?api=1'
            '&destination=${dest.latitude},${dest.longitude}'
            '&travelmode=driving'
        : 'https://www.google.com/maps/dir/?api=1'
            '&destination=${dest.latitude},${dest.longitude}'
            '&waypoints=$waypointStr'
            '&travelmode=driving';

    // iOS: comgooglemaps:// → maps.apple.com → web fallback
    if (Platform.isIOS) {
      final iosUrl = tasks.length == 1
          ? 'comgooglemaps://?daddr=${dest.latitude},${dest.longitude}&directionsmode=driving'
          : 'comgooglemaps://?daddr=${dest.latitude},${dest.longitude}'
              '&waypoints=$waypointStr&directionsmode=driving';
      if (await canLaunchUrl(Uri.parse(iosUrl))) {
        await launchUrl(Uri.parse(iosUrl));
        return;
      }
      final appleUrl = 'https://maps.apple.com/?daddr=${dest.latitude},${dest.longitude}&dirflg=d';
      if (await canLaunchUrl(Uri.parse(appleUrl))) {
        await launchUrl(Uri.parse(appleUrl), mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Android / iOS web fallback
    final uri = Uri.parse(webUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         const Text('Harita uygulaması açılamadı.'),
        backgroundColor: AppColors.danger,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Helpers ────────────────────────────────────────────────
  String _algoLabel(String algo) {
    switch (algo) {
      case 'genetic':             return 'Genetik';
      case 'simulated_annealing': return 'Sim. Tavlama';
      case 'ant_colony':          return 'Karınca (ACO)';
      case 'tabu_search':         return 'Tabu Arama';
      case 'lin_kernighan':       return 'Lin-Kernighan';
      default:                    return algo;
    }
  }

  IconData _algoIcon(String algo) {
    switch (algo) {
      case 'genetic':             return Icons.psychology_outlined;
      case 'simulated_annealing': return Icons.thermostat_outlined;
      case 'ant_colony':          return Icons.hive_outlined;
      case 'tabu_search':         return Icons.search_outlined;
      case 'lin_kernighan':       return Icons.route_outlined;
      default:                    return Icons.bolt_outlined;
    }
  }

  Color _algoColor(String algo) {
    switch (algo) {
      case 'genetic':             return const Color(0xFF3D9CF5);
      case 'simulated_annealing': return AppColors.orange;
      case 'ant_colony':          return AppColors.warn;
      case 'tabu_search':         return const Color(0xFF9C6FE4);
      case 'lin_kernighan':       return AppColors.success;
      default:                    return const Color(0xFF888888);
    }
  }

  Color _priorityColor(int priority) {
    switch (priority) {
      case 5: return AppColors.prio5;
      case 4: return AppColors.prio4;
      case 3: return AppColors.prio3;
      case 2: return AppColors.prio2;
      default: return AppColors.prio1;
    }
  }
}

class _NavBanner extends StatelessWidget {
  final NavState     state;
  final VoidCallback onStop;
  const _NavBanner({required this.state, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final task = state.currentTask;
    return Container(
      color:   AppColors.success,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        const Icon(Icons.near_me_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task?.name ?? 'Navigasyon',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '\${state.distanceLabel} uzakta  ·  \${state.etaLabel}  ·  '
                '\${state.currentTaskIdx + 1}/\${state.totalTasks}. durak',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ])),
        TextButton(
          onPressed: onStop,
          style:     TextButton.styleFrom(foregroundColor: Colors.white),
          child:     const Text('Durdur', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}