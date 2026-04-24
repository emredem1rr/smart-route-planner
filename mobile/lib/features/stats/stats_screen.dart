import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/auth_service.dart';
import '../../core/models/task_model.dart';
import '../../core/theme/app_theme.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  late TabController _tab;

  bool _loading = true;
  List<TaskModel> _tasks = [];

  // Haftalık veri
  Map<String, int> _weeklyDone    = {};
  Map<String, int> _weeklyPending = {};

  // Kategori verisi (önceliğe göre)
  Map<int, int> _byPriority = {};

  // Genel
  int _totalDone = 0, _totalPending = 0, _totalCancelled = 0;
  double _completionRate = 0;
  int _streak = 0;

  // Rota istatistikleri
  int    _totalRoutes    = 0;
  double _totalKmSaved   = 0;
  String _topAlgo        = '';
  List<Map<String, dynamic>> _routeHistory = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadStats();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final now  = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final fromStr = '${from.year}-${from.month.toString().padLeft(2,'0')}-${from.day.toString().padLeft(2,'0')}';
      final toStr   = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

      final tasks   = await _auth.getRemoteTasks(dateFrom: fromStr, dateTo: toStr);
      final history = await _auth.getRouteHistory();
      _tasks        = tasks;
      _routeHistory = history;
      _compute();
      _computeRouteStats();
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _computeRouteStats() {
    _totalRoutes = _routeHistory.length;
    if (_routeHistory.isEmpty) return;

    // Toplam km — total_distance alanından
    double totalKm = 0;
    for (final r in _routeHistory) {
      totalKm += (r['total_distance'] as num? ?? 0).toDouble();
    }
    _totalKmSaved = double.parse(totalKm.toStringAsFixed(1));

    // En çok kullanılan algoritma
    final algoCounts = <String, int>{};
    for (final r in _routeHistory) {
      final a = r['algorithm_used'] as String? ?? '';
      if (a.isNotEmpty) algoCounts[a] = (algoCounts[a] ?? 0) + 1;
    }
    if (algoCounts.isNotEmpty) {
      _topAlgo = algoCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
  }

  void _compute() {
    _totalDone      = _tasks.where((t) => t.status == 'done').length;
    _totalPending   = _tasks.where((t) => t.status == 'pending').length;
    _totalCancelled = _tasks.where((t) => t.status == 'cancelled').length;
    final total     = _tasks.length;
    _completionRate = total == 0 ? 0 : _totalDone / total;

    // Haftalık — son 7 gün
    _weeklyDone    = {};
    _weeklyPending = {};
    for (int i = 6; i >= 0; i--) {
      final d   = DateTime.now().subtract(Duration(days: i));
      final key = '${d.day}.${d.month}';
      _weeklyDone[key]    = 0;
      _weeklyPending[key] = 0;
    }
    for (final t in _tasks) {
      final parts = t.taskDate.split('-');
      if (parts.length != 3) continue;
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final key = '${d.day}.${d.month}';
      if (_weeklyDone.containsKey(key)) {
        if (t.status == 'done')    _weeklyDone[key] = (_weeklyDone[key] ?? 0) + 1;
        if (t.status == 'pending') _weeklyPending[key] = (_weeklyPending[key] ?? 0) + 1;
      }
    }

    // Önceliğe göre
    _byPriority = {1:0, 2:0, 3:0, 4:0, 5:0};
    for (final t in _tasks) {
      _byPriority[t.priority] = (_byPriority[t.priority] ?? 0) + 1;
    }

    // Streak — arka arkaya kaç gün görev tamamlandı
    _streak = 0;
    for (int i = 0; i < 30; i++) {
      final d      = DateTime.now().subtract(Duration(days: i));
      final dStr   = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      final hasDone = _tasks.any((t) => t.taskDate == dStr && t.status == 'done');
      if (hasDone) _streak++; else break;
    }
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
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('İstatistikler', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: ts),
            onPressed: _loadStats,
          ),
        ],
        bottom: TabBar(
          controller:          _tab,
          labelColor:          AppColors.orange,
          unselectedLabelColor: ts,
          indicatorColor:      AppColors.orange,
          indicatorSize:       TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Genel'),
            Tab(text: 'Haftalık'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : TabBarView(
        controller: _tab,
        children: [
          _buildGeneralTab(surf, border, tp, ts),
          _buildWeeklyTab(surf, border, tp, ts),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(Color surf, Color border, Color tp, Color ts) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Streak kartı
        if (_streak > 0)
          Container(
            margin:  const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.orange, AppColors.orange.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 36)),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_streak Gün Üst Üste!',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const Text('Harika gidiyorsun, devam et!',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ]),
          ),

        // Özet kartlar
        Row(children: [
          Expanded(child: _statCard('$_totalDone', 'Tamamlandı',
              AppColors.success, Icons.check_circle_outline, surf, border)),
          const SizedBox(width: 10),
          Expanded(child: _statCard('$_totalPending', 'Bekleyen',
              AppColors.warn, Icons.pending_actions_rounded, surf, border)),
          const SizedBox(width: 10),
          Expanded(child: _statCard('$_totalCancelled', 'İptal',
              AppColors.danger, Icons.cancel_outlined, surf, border)),
        ]),
        const SizedBox(height: 16),

        // Tamamlanma oranı
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: surf, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tamamlanma Oranı',
                style: TextStyle(color: ts, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [
              Text('${(_completionRate * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: tp, fontSize: 32,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value:           _completionRate,
                    minHeight:       10,
                    color:           AppColors.success,
                    backgroundColor: AppColors.border(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Son 30 günde $_totalDone/${_tasks.length} görev',
                    style: TextStyle(color: ts, fontSize: 11)),
              ],
              )),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // Rota istatistikleri
        if (_totalRoutes > 0) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: surf, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.route_rounded, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 10),
                Text('Rota Optimizasyonları',
                    style: TextStyle(color: ts, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _statCard('$_totalRoutes', 'Toplam Rota',
                    const Color(0xFF6366F1), Icons.route_rounded, surf, border)),
                const SizedBox(width: 10),
                Expanded(child: _statCard('${_totalKmSaved.toStringAsFixed(0)} km', 'Toplam Mesafe',
                    AppColors.info, Icons.straighten_rounded, surf, border)),
              ]),
              if (_topAlgo.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.psychology_outlined, color: Color(0xFF6366F1), size: 14),
                    const SizedBox(width: 8),
                    Text('En çok kullanılan: ${_algoLabel(_topAlgo)}',
                        style: const TextStyle(color: Color(0xFF6366F1),
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Önceliğe göre dağılım
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: surf, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Öncelik Dağılımı',
                style: TextStyle(color: ts, fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ...[1, 2, 3, 4, 5].map((p) {
              final count = _byPriority[p] ?? 0;
              final total = _tasks.isEmpty ? 1 : _tasks.length;
              final pct   = count / total;
              final colors = [AppColors.prio1, AppColors.prio2, AppColors.prio3,
                AppColors.prio4, AppColors.prio5];
              final labels = ['Çok Düşük', 'Düşük', 'Orta', 'Yüksek', 'Çok Yüksek'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(width: 80,
                      child: Text(labels[p-1],
                          style: TextStyle(color: ts, fontSize: 12))),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct, minHeight: 8,
                      color: colors[p-1],
                      backgroundColor: colors[p-1].withOpacity(0.12),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Text('$count', style: TextStyle(color: ts, fontSize: 12)),
                ]),
              );
            }),
          ]),
        ),
      ],
    );
  }

  Widget _buildWeeklyTab(Color surf, Color border, Color tp, Color ts) {
    final days    = _weeklyDone.keys.toList();
    final maxVal  = [
      ..._weeklyDone.values,
      ..._weeklyPending.values,
    ].fold<int>(0, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Son 7 Gün', style: TextStyle(color: tp,
            fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Tamamlanan ve bekleyen görevler',
            style: TextStyle(color: ts, fontSize: 13)),
        const SizedBox(height: 16),

        Container(
          height:  220,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
              color: surf, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border)),
          child: BarChart(BarChartData(
            maxY:      (maxVal + 2).toDouble(),
            gridData:  FlGridData(
              show: true,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: border, strokeWidth: 0.7),
              drawVerticalLine: false,
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: TextStyle(color: ts, fontSize: 10)),
              )),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= days.length) return const SizedBox();
                  return Text(days[idx],
                      style: TextStyle(color: ts, fontSize: 10));
                },
              )),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            barGroups: List.generate(days.length, (i) {
              final day = days[i];
              return BarChartGroupData(
                x:        i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY:       (_weeklyDone[day] ?? 0).toDouble(),
                    color:     AppColors.success,
                    width:     12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  BarChartRodData(
                    toY:       (_weeklyPending[day] ?? 0).toDouble(),
                    color:     AppColors.warn.withOpacity(0.7),
                    width:     12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            }),
          )),
        ),
        const SizedBox(height: 12),

        // Legend
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legendItem(AppColors.success, 'Tamamlandı', ts),
          const SizedBox(width: 20),
          _legendItem(AppColors.warn.withOpacity(0.7), 'Bekleyen', ts),
        ]),
        const SizedBox(height: 24),

        // Günlük detay
        ...List.generate(days.length, (i) {
          final day  = days[i];
          final done = _weeklyDone[day]    ?? 0;
          final pend = _weeklyPending[day] ?? 0;
          if (done + pend == 0) return const SizedBox();
          return Container(
            margin:  const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: surf, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border)),
            child: Row(children: [
              Text(day, style: TextStyle(color: ts, fontSize: 13,
                  fontWeight: FontWeight.w600)),
              const Spacer(),
              if (done > 0) ...[
                Icon(Icons.check_circle, color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Text('$done tamamlandı',
                    style: TextStyle(color: AppColors.success, fontSize: 12)),
                const SizedBox(width: 12),
              ],
              if (pend > 0) ...[
                Icon(Icons.pending, color: AppColors.warn, size: 14),
                const SizedBox(width: 4),
                Text('$pend bekleyen',
                    style: TextStyle(color: AppColors.warn, fontSize: 12)),
              ],
            ]),
          );
        }),
      ],
    );
  }

  Widget _statCard(String value, String label, Color color,
      IconData icon, Color surf, Color border) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: surf, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border)),
      child: Column(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color,
            fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: AppColors.textSecond(context),
            fontSize: 11)),
      ]),
    );
  }

  String _algoLabel(String key) {
    switch (key) {
      case 'genetic':             return 'Genetik Algoritma';
      case 'simulated_annealing': return 'Simüle Tavlama';
      case 'ant_colony':          return 'Karınca Kolonisi';
      case 'tabu_search':         return 'Tabu Arama';
      case 'lin_kernighan':       return 'Lin-Kernighan';
      default:                    return key;
    }
  }

  Widget _legendItem(Color color, String label, Color ts) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12,
          decoration: BoxDecoration(color: color,
              borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: ts, fontSize: 12)),
    ]);
  }
}