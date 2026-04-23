import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});
  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  bool          _loading = false;
  int           _elapsed = 0;   // saniye cinsinden geçen süre
  Timer?        _timer;
  List<dynamic> _results = [];
  String        _dataset = '';
  int           _nCities = 0;
  String        _winner  = '';
  String?       _error;

  // Kullanıcının grafik için seçtiği algoritmalar
  final Set<String> _selectedAlgos = {
    'genetic', 'simulated_annealing', 'ant_colony', 'tabu_search', 'lin_kernighan'
  };

  // Geçmiş sonuçlar
  List<Map<String, dynamic>> _history = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final raw = await StorageService().getString('benchmark_history');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() => _history = list.cast<Map<String, dynamic>>());
      } catch (_) {}
    }
  }

  Future<void> _saveToHistory() async {
    final entry = {
      'date'    : DateTime.now().toIso8601String(),
      'dataset' : _dataset,
      'n_cities': _nCities,
      'winner'  : _winner,
      'results' : _results.map((r) => {
        'algorithm'     : r['algorithm'],
        'tour_length'   : r['tour_length'],
        'gap_percent'   : r['gap_percent'],
        'execution_time_ms': r['execution_time_ms'],
      }).toList(),
    };
    _history.add(entry);
    if (_history.length > 10) _history = _history.sublist(_history.length - 10);
    await StorageService().setString('benchmark_history', jsonEncode(_history));
  }

  static const _algoKeys = [
    'genetic', 'simulated_annealing', 'ant_colony', 'tabu_search', 'lin_kernighan'
  ];

  String _algoLabel(String key) {
    switch (key) {
      case 'genetic':             return 'Genetik Algoritma';
      case 'simulated_annealing': return 'Simüle Tavlama';
      case 'ant_colony':          return 'Karınca Kolonisi (ACS)';
      case 'tabu_search':         return 'Tabu Arama';
      case 'lin_kernighan':       return 'Lin-Kernighan (LKH)';
      default:                    return key;
    }
  }

  Future<void> _runBenchmark() async {
    setState(() { _loading = true; _elapsed = 0; _error = null; _results = []; _winner = ''; });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    try {
      final response = await http
          .get(Uri.parse('${ApiConstants.optimizationBaseUrl}/benchmark/berlin52'))
          .timeout(const Duration(seconds: 300));
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        setState(() {
          _results = json['results'] as List;
          _dataset = json['dataset'] as String;
          _nCities = json['n_cities'] as int;
          _winner  = json['winner']  as String? ?? '';
        });
        await _saveToHistory();
      } else {
        setState(() => _error = 'Benchmark başarısız: ${json['error'] ?? ''}');
      }
    } catch (e) {
      setState(() => _error = 'Sunucuya bağlanılamadı: $e');
    } finally {
      _timer?.cancel();
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t      = context.watch<SettingsProvider>().t;
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
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.surfaceHigh(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border)),
            child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
          ),
        ),
        title: Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.science_rounded, color: Colors.white, size: 15)),
          const SizedBox(width: 10),
          Text(t('benchmark'), style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: Icon(
                _showHistory ? Icons.history_toggle_off : Icons.history,
                color: _showHistory ? AppColors.orange : tp,
              ),
              tooltip: 'Geçmiş Sonuçlar',
              onPressed: () => setState(() => _showHistory = !_showHistory),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Geçmiş Paneli ────────────────────────────
            if (_showHistory && _history.isNotEmpty) ...[
              Row(children: [
                Text('Geçmiş Sonuçlar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tp)),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    setState(() => _history = []);
                    await StorageService().setString('benchmark_history', '[]');
                  },
                  child: Text('Temizle',
                      style: TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
              ]),
              const SizedBox(height: 8),
              ..._history.reversed.map((h) {
                final date   = DateTime.tryParse(h['date'] as String? ?? '');
                final dateStr = date != null
                    ? '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2,'0')}'
                    : '';
                final results = (h['results'] as List?) ?? [];
                return Container(
                  margin:  const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        surf,
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 13, color: ts),
                      const SizedBox(width: 5),
                      Text(dateStr, style: TextStyle(color: ts, fontSize: 12)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('🏆 ${_algoLabel(h['winner'] as String? ?? '')}',
                            style: const TextStyle(
                                color: AppColors.success, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: results.map<Widget>((r) {
                      final gap = (r['gap_percent'] as num).toDouble();
                      final gc  = gap < 10 ? AppColors.success
                          : gap < 25 ? AppColors.warn : AppColors.danger;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color:        gc.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border:       Border.all(color: gc.withOpacity(0.3)),
                        ),
                        child: Text(
                          '${_algoLabel(r['algorithm'] as String)}  %${gap.toStringAsFixed(1)}',
                          style: TextStyle(fontSize: 10, color: gc),
                        ),
                      );
                    }).toList()),
                  ]),
                );
              }),
              Divider(height: 24, color: border),
            ],

            // ── Bilgi kartı ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        AppColors.info.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppColors.info.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.science_outlined, color: AppColors.info, size: 18),
                    const SizedBox(width: 8),
                    Text('Berlin52 Testi',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.info)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '52 şehirli klasik TSP problemi. Optimal çözüm = 7542 birim. '
                        '5 algoritmanın optimale yakınlığını ve hızını karşılaştırır.',
                    style: TextStyle(color: ts, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Başlat butonu ────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _runBenchmark,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  _loading ? 'Çalışıyor...' : 'Benchmark Başlat',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _loading ? AppColors.textDim(context) : AppColors.orange,
                  foregroundColor: Colors.white,
                  padding:   const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            if (_loading) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    minHeight: 4, backgroundColor: border, color: AppColors.orange),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Genetik · SA · ACO · Tabu · LKH test ediliyor...',
                      style: TextStyle(color: ts, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:        AppColors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:       Border.all(color: AppColors.orange.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.timer_outlined, size: 12, color: AppColors.orange),
                      const SizedBox(width: 4),
                      Text(
                        '${_elapsed ~/ 60 > 0 ? '${_elapsed ~/ 60}d ' : ''}${_elapsed % 60}s',
                        style: const TextStyle(
                          color:      AppColors.orange,
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        AppColors.dangerDim,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: AppColors.danger.withOpacity(0.5)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                ]),
              ),
            ],

            // ── Sonuçlar ─────────────────────────────────
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 24),

              // Kazanan
              if (_winner.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin:  const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color:        AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: AppColors.success.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.emoji_events_rounded, color: AppColors.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Kazanan: ${_algoLabel(_winner)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 15))),
                    Text(
                      '${_elapsed ~/ 60 > 0 ? '${_elapsed ~/ 60}d ' : ''}${_elapsed % 60}s',
                      style: TextStyle(color: AppColors.success.withOpacity(0.7), fontSize: 12),
                    ),
                  ]),
                ),

              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        AppColors.surfaceHigh(context),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: border),
                  ),
                  child: Text('$_dataset  •  $_nCities şehir',
                      style: TextStyle(color: tp, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 14),

              // Algoritma kartları
              ..._results.asMap().entries.map((entry) {
                final r       = entry.value;
                final key     = r['algorithm'] as String;
                final gap     = (r['gap_percent'] as num).toDouble();
                final isWin   = key == _winner;
                final gapColor = gap < 10 ? AppColors.success
                    : gap < 25 ? AppColors.warn : AppColors.danger;
                final ac = algoColor(key);
                final ai = algoIcon(key);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:        surf,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isWin ? AppColors.success.withOpacity(0.5) : border,
                      width: isWin ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: ac.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                          child: Icon(ai, color: ac, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_algoLabel(key),
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14,
                                color: isWin ? AppColors.success : tp))),
                        if (isWin) ...[
                          const Icon(Icons.emoji_events_rounded, color: AppColors.success, size: 16),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color:        gapColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border:       Border.all(color: gapColor.withOpacity(0.4)),
                          ),
                          child: Text('%${gap.toStringAsFixed(1)} uzak',
                              style: TextStyle(color: gapColor, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (r['optimal_length'] as num) / (r['tour_length'] as num),
                          minHeight: 8, backgroundColor: border,
                          valueColor: AlwaysStoppedAnimation<Color>(gapColor),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tur: ${(r['tour_length'] as num).toStringAsFixed(1)}'
                            '  |  Optimal: ${(r['optimal_length'] as num).toStringAsFixed(1)}'
                            '  |  ${(r['execution_time_ms'] as num).toStringAsFixed(1)} ms',
                        style: TextStyle(fontSize: 12, color: ts),
                      ),
                    ],
                  ),
                );
              }),

              // ── Grafik başlığı + algoritma seçici ────
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Fitness Gelişimi',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tp)),
                  const Spacer(),
                  Text('Filtrele:', style: TextStyle(fontSize: 12, color: ts)),
                ],
              ),
              const SizedBox(height: 8),

              // Algoritma toggle butonları
              Wrap(
                spacing: 6, runSpacing: 6,
                children: _algoKeys.map((key) {
                  final selected = _selectedAlgos.contains(key);
                  final color    = algoColor(key);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        if (_selectedAlgos.length > 1) _selectedAlgos.remove(key);
                      } else {
                        _selectedAlgos.add(key);
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: selected ? color.withOpacity(0.15) : AppColors.surfaceHigh(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? color : border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: selected ? color : AppColors.textDim(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(_algoLabel(key),
                            style: TextStyle(
                              fontSize: 11,
                              color: selected ? color : AppColors.textDim(context),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            )),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),

              // Grafik
              Container(
                height:     220,
                padding:    const EdgeInsets.fromLTRB(8, 12, 16, 8),
                decoration: BoxDecoration(
                  color:        surf,
                  borderRadius: BorderRadius.circular(14),
                  border:       Border.all(color: border),
                ),
                child: _buildChart(border, ts),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChart(Color border, Color ts) {
    if (_results.isEmpty) return const SizedBox();

    final lines    = <LineChartBarData>[];
    double globalMin = double.infinity;
    double globalMax = double.negativeInfinity;

    // Seçili algoritmaların fitness aralığını bul
    for (final r in _results) {
      final key = r['algorithm'] as String;
      if (!_selectedAlgos.contains(key)) continue;
      final history = (r['fitness_history'] as List)
          .map((v) => (v as num).toDouble())
          .toList();
      if (history.isEmpty) continue;
      final mn = history.reduce((a, b) => a < b ? a : b);
      final mx = history.reduce((a, b) => a > b ? a : b);
      if (mn < globalMin) globalMin = mn;
      if (mx > globalMax) globalMax = mx;
    }

    if (globalMin == double.infinity) return const SizedBox();

    // Y ekseni padding
    final yPadding = (globalMax - globalMin) * 0.1;
    final yMin     = globalMin - yPadding;
    final yMax     = globalMax + yPadding;

    for (final r in _results) {
      final key = r['algorithm'] as String;
      if (!_selectedAlgos.contains(key)) continue;
      final history = (r['fitness_history'] as List)
          .map((v) => (v as num).toDouble())
          .toList();
      if (history.isEmpty) continue;

      lines.add(LineChartBarData(
        spots: history.asMap().entries
            .map((e) => FlSpot(e.key.toDouble(), e.value))
            .toList(),
        isCurved:     true,
        color:        algoColor(key),
        barWidth:     2,
        dotData:      const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

    return LineChart(LineChartData(
      minY:        yMin,
      maxY:        yMax,
      lineBarsData: lines,
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => FlLine(color: border, strokeWidth: 1),
        getDrawingVerticalLine:   (_) => FlLine(color: border, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: border)),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles:   true,
            reservedSize: 52,
            getTitlesWidget: (v, _) => Text(
              v.toStringAsFixed(2),
              style: TextStyle(fontSize: 7, color: ts),
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
}