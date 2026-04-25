import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import '../../core/constants/api_constants.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';

class RouteHistoryScreen extends StatefulWidget {
  const RouteHistoryScreen({super.key});
  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  final _storage = StorageService();
  bool _loading  = true;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _storage.getToken();
      final resp  = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/routes/history'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        setState(() =>
            _routes = List<Map<String, dynamic>>.from(data['routes']));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  // ── Helpers ───────────────────────────────────────────────
  String _algoLabel(String algo) {
    switch (algo) {
      case 'lin_kernighan':       return 'LKH';
      case 'ant_colony':          return 'ACO';
      case 'simulated_annealing': return 'SA';
      case 'tabu_search':         return 'Tabu';
      case 'genetic':             return 'Genetik';
      default: return algo.isEmpty ? '—' : algo;
    }
  }

  String _algoFull(String algo) {
    switch (algo) {
      case 'lin_kernighan':       return 'Lin-Kernighan';
      case 'ant_colony':          return 'Karınca Kolonisi';
      case 'simulated_annealing': return 'Simüle Tavlama';
      case 'tabu_search':         return 'Tabu Arama';
      case 'genetic':             return 'Genetik Algoritma';
      default: return algo;
    }
  }

  Color _algoColor(String algo) {
    switch (algo) {
      case 'lin_kernighan':       return const Color(0xFF4CAF50);
      case 'ant_colony':          return const Color(0xFFE91E63);
      case 'simulated_annealing': return const Color(0xFFFF9800);
      case 'tabu_search':         return const Color(0xFF9C27B0);
      case 'genetic':             return const Color(0xFF2196F3);
      default: return AppColors.orange;
    }
  }

  // Last 7 days bar chart data
  List<BarChartGroupData> _buildBarGroups(Color barColor) {
    final today = DateTime.now();
    return List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      final dayStr = '${day.year}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      final total = _routes
          .where((r) => r['task_date']?.toString().substring(0, 10) == dayStr)
          .fold(0.0, (sum, r) => sum + (r['total_distance'] ?? 0.0));
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY:              total.toDouble(),
          color:            total > 0 ? barColor : barColor.withOpacity(0.15),
          width:            20,
          borderRadius:     const BorderRadius.vertical(top: Radius.circular(5)),
        ),
      ]);
    });
  }

  // Most-used algorithm
  String _topAlgo() {
    if (_routes.isEmpty) return '';
    final counts = <String, int>{};
    for (final r in _routes) {
      final a = r['algorithm_used']?.toString() ?? '';
      if (a.isNotEmpty) counts[a] = (counts[a] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // Show tasks in this route
  void _showReloadSheet(Map<String, dynamic> route) {
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final names  = route['task_names']?.toString() ?? '';
    final tasks  = names.isNotEmpty ? names.split(', ') : <String>[];

    showModalBottomSheet(
      context:         context,
      backgroundColor: surf,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Rota Görevleri',
                style: TextStyle(color: tp,
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(route['task_date']?.toString().substring(0, 10) ?? '',
                style: TextStyle(color: ts, fontSize: 13)),
            const SizedBox(height: 16),
            if (tasks.isEmpty)
              Text('Görev bilgisi bulunamadı.',
                  style: TextStyle(color: ts, fontSize: 13))
            else
              ...tasks.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.orange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text('${e.key + 1}',
                        style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.value.trim(),
                      style: TextStyle(color: tp, fontSize: 14))),
                ]),
              )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '${tasks.length} görev görev listesine taşındı'),
                    backgroundColor: AppColors.success,
                    behavior:        SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
                },
                icon:  const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Bu Rotayı Tekrar Yükle',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding:         const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor:  surf,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight:    64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
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
            child: const Icon(Icons.history_rounded, color: Colors.white,
                size: 15),
          ),
          const SizedBox(width: 10),
          Text('Rota Geçmişi',
              style: TextStyle(color: tp, fontSize: 16,
                  fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          IconButton(
            icon:      Icon(Icons.refresh_rounded, color: ts),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.orange))
          : _routes.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.route_outlined, size: 56, color: ts),
              const SizedBox(height: 12),
              Text('Henüz rota geçmişi yok',
                  style: TextStyle(color: ts, fontSize: 15)),
              const SizedBox(height: 6),
              Text('Rota optimize ettikçe burada görünür',
                  style: TextStyle(color: ts, fontSize: 12)),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Son 7 gün bar chart ──────────────────────
                _buildChartCard(surf, border, tp, ts),
                const SizedBox(height: 12),

                // ── En çok kullanılan algoritma rozeti ───────
                _buildTopAlgoBadge(surf, border, tp, ts),
                const SizedBox(height: 16),

                Text('Tüm Rotalar',
                    style: TextStyle(color: tp,
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),

                // ── Rota listesi ─────────────────────────────
                ..._routes.map((r) => _routeCard(r, surf, border, tp, ts)),
              ],
            ),
    );
  }

  Widget _buildChartCard(
      Color surf, Color border, Color tp, Color ts) {
    final barColor = AppColors.orange;
    final groups   = _buildBarGroups(barColor);
    final today    = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bar_chart_rounded, color: AppColors.orange,
              size: 16),
          const SizedBox(width: 6),
          Text('Son 7 Gün — Rota Mesafeleri',
              style: TextStyle(color: tp,
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: BarChart(BarChartData(
            barGroups:      groups,
            titlesData:     FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  reservedSize: 36,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toStringAsFixed(0)} km',
                    style: TextStyle(color: ts, fontSize: 9),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final d = today.subtract(
                        Duration(days: 6 - v.toInt()));
                    final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum',
                      'Cmt', 'Paz'];
                    return Text(days[d.weekday - 1],
                        style: TextStyle(color: ts, fontSize: 9));
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            gridData:  FlGridData(
              show: true,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: border, strokeWidth: 0.6),
              getDrawingVerticalLine:   (_) =>
                  const FlLine(color: Colors.transparent),
            ),
            borderData: FlBorderData(show: false),
          )),
        ),
      ]),
    );
  }

  Widget _buildTopAlgoBadge(
      Color surf, Color border, Color tp, Color ts) {
    final top = _topAlgo();
    if (top.isEmpty) return const SizedBox.shrink();
    final color = _algoColor(top);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color:        color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.emoji_events_rounded,
              color: Colors.amber, size: 20),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('En Çok Kullanılan Algoritma',
              style: TextStyle(color: ts, fontSize: 11)),
          const SizedBox(height: 2),
          Text(_algoFull(top),
              style: TextStyle(color: color,
                  fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _routeCard(Map<String, dynamic> r,
      Color surf, Color border, Color tp, Color ts) {
    final algo  = r['algorithm_used']?.toString() ?? '';
    final color = _algoColor(algo);
    final date  = r['task_date']?.toString().substring(0, 10) ?? '';
    final dist  = (r['total_distance']    ?? 0.0).toDouble();
    final time  = (r['total_travel_time'] ?? 0.0).toDouble();
    final count = r['task_count'] ?? 0;
    final names = r['task_names']?.toString() ?? '';

    return Container(
      margin:  const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_algoLabel(algo),
                style: TextStyle(color: color,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(date, style: TextStyle(color: ts, fontSize: 12)),
          const Spacer(),
          Text('$count görev', style: TextStyle(color: ts, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _stat(Icons.route_outlined,
              '${dist.toStringAsFixed(1)} km', ts),
          const SizedBox(width: 16),
          _stat(Icons.timer_outlined,
              '${time.toStringAsFixed(0)} dk', ts),
        ]),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(names,
              style: TextStyle(color: ts, fontSize: 11),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => _showReloadSheet(r),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.orange.withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.replay_rounded,
                    size: 13, color: AppColors.orange),
                const SizedBox(width: 5),
                const Text('Bu rotayı tekrar yükle',
                    style: TextStyle(
                        color:      AppColors.orange,
                        fontSize:   11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _stat(IconData icon, String label, Color ts) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: ts),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: ts, fontSize: 12)),
    ]);
  }
}
