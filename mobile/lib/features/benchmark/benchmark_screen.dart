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
  int           _elapsed = 0;
  Timer?        _timer;
  List<dynamic> _results = [];
  String        _dataset = '';
  int           _nCities = 0;
  String        _winner  = '';
  String?       _error;

  // Dataset seçimi
  String _selectedDataset = 'berlin52';
  static const _datasetInfo = {
    'berlin52': {
      'label'  : 'Berlin52',
      'desc'   : '52 şehir · Optimal = 7.542',
      'n'      : 52,
      'optimal': 7542,
      'endpoint': '/benchmark/berlin52',
    },
    'kroa100': {
      'label'  : 'kroA100',
      'desc'   : '100 şehir · Optimal = 21.282',
      'n'      : 100,
      'optimal': 21282,
      'endpoint': '/benchmark/kroa100',
    },
    'pr76': {
      'label'  : 'pr76',
      'desc'   : '76 şehir · Optimal = 108.159',
      'n'      : 76,
      'optimal': 108159,
      'endpoint': '/benchmark/pr76',
    },
  };

  // Kullanıcının grafik için seçtiği algoritmalar
  final Set<String> _selectedAlgos = {
    'genetic', 'simulated_annealing', 'ant_colony', 'tabu_search', 'lin_kernighan'
  };

  // Geçmiş sonuçlar
  List<Map<String, dynamic>> _history = [];
  bool _showHistory = false;

  // Gerçek Hayat sekmesi
  bool          _rwLoading   = false;
  String?       _rwError;
  List<dynamic> _rwScenarios = [];

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
    final endpoint = _datasetInfo[_selectedDataset]!['endpoint'] as String;
    try {
      final response = await http
          .get(Uri.parse('${ApiConstants.optimizationBaseUrl}$endpoint'))
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

  Future<void> _runRealWorld() async {
    setState(() { _rwLoading = true; _rwError = null; _rwScenarios = []; });
    try {
      final response = await http
          .get(Uri.parse('${ApiConstants.optimizationBaseUrl}/benchmark/real-world'))
          .timeout(const Duration(seconds: 300));
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _rwScenarios = data['scenarios'] as List);
      } else {
        setState(() => _rwError = data['error'] ?? 'Hata oluştu.');
      }
    } catch (e) {
      setState(() => _rwError = 'Sunucuya bağlanılamadı: $e');
    } finally {
      setState(() => _rwLoading = false);
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            Divider(height: 1, color: border),
            TabBar(
              indicatorColor:       AppColors.orange,
              indicatorWeight:      2.5,
              labelColor:           AppColors.orange,
              unselectedLabelColor: ts,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(icon: Icon(Icons.science_outlined,     size: 16), text: 'TSP Klasik'),
                Tab(icon: Icon(Icons.location_city_rounded, size: 16), text: 'Gerçek Hayat'),
              ],
            ),
          ]),
        ),
      ),
      body: TabBarView(
        children: [
          SingleChildScrollView(
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

            // ── Dataset Seçici ───────────────────────────
            Row(children: [
              Text('Dataset:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: tp)),
              const SizedBox(width: 10),
              ..._datasetInfo.entries.map((e) {
                final sel   = _selectedDataset == e.key;
                final label = e.value['label'] as String;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDataset = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:        sel ? AppColors.orange.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border:       Border.all(
                        color: sel ? AppColors.orange : border,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(label, style: TextStyle(
                      fontSize: 12,
                      color:      sel ? AppColors.orange : ts,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    )),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 12),

            // ── Bilgi kartı ──────────────────────────────
            Builder(builder: (_) {
              final info = _datasetInfo[_selectedDataset]!;
              return Container(
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
                      Text('${info['label']} Testi',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.info)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      '${info['n']} şehirli TSP problemi. Optimal = ${info['optimal']}. '
                      '5 algoritmanın optimale yakınlığını (gap%) ve hızını karşılaştırır.',
                      style: TextStyle(color: ts, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              );
            }),
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
                  Text('${_datasetInfo[_selectedDataset]!['label']} · 5 algoritma test ediliyor...',
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
          _buildRealWorldTab(surf, border, tp, ts),
        ],
      ),
    )); // DefaultTabController
  }

  // ── Gerçek Hayat Sekmesi ────────────────────────────────────────────────────
  Widget _buildRealWorldTab(Color surf, Color border, Color tp, Color ts) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Açıklama kartı
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        const Color(0xFF6366F1).withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: const Color(0xFF6366F1).withOpacity(0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.location_city_rounded, color: Color(0xFF6366F1), size: 18),
              SizedBox(width: 8),
              Text('Gerçek Hayat Senaryoları',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                      color: Color(0xFF6366F1))),
            ]),
            const SizedBox(height: 8),
            Text(
              'Samsun ve Amasya koordinatlı gerçek senaryolar: '
              'Kurye (10 durak), Satış Temsilcisi (7 durak), Sağlık Ziyaretçisi (5 durak). '
              'Tüm senaryolar 5 algoritmayla çözülür, Gemini sonuçları yorumlar.',
              style: TextStyle(color: ts, fontSize: 13, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Başlat butonu
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _rwLoading ? null : _runRealWorld,
            icon: _rwLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(
              _rwLoading ? 'Senaryolar çalışıyor...' : 'Senaryoları Çalıştır',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _rwLoading ? AppColors.textDim(context) : const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding:   const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        if (_rwLoading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                minHeight: 4, backgroundColor: border,
                color: const Color(0xFF6366F1)),
          ),
        ],

        if (_rwError != null) ...[
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
              Expanded(child: Text(_rwError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13))),
            ]),
          ),
        ],

        if (_rwScenarios.isNotEmpty) ...[
          const SizedBox(height: 20),
          ..._rwScenarios.map((sc) => _buildScenarioCard(sc, surf, border, tp, ts)),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildScenarioCard(dynamic sc, Color surf, Color border, Color tp, Color ts) {
    final label       = sc['label']              as String;
    final city        = sc['city']               as String;
    final nStops      = sc['n_stops']            as int;
    final winner      = sc['winner']             as String;
    final winnerDist  = (sc['winner_distance_km'] as num).toDouble();
    final aiInterp    = sc['ai_interpretation']  as String? ?? '';
    final results     = (sc['results']           as List).cast<Map<String, dynamic>>();

    return Container(
      margin:  const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Başlık
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:        const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(city, style: const TextStyle(
                color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: tp))),
          Text('$nStops durak', style: TextStyle(color: ts, fontSize: 12)),
        ]),
        const SizedBox(height: 10),

        // Kazanan chip
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:        AppColors.success.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.emoji_events_rounded, color: AppColors.success, size: 16),
            const SizedBox(width: 8),
            Text('${_algoLabel(winner)}  ·  ${winnerDist.toStringAsFixed(2)} km',
                style: const TextStyle(color: AppColors.success,
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 10),

        // Algoritma sonuçları
        ...results.map((r) {
          final algo  = r['algorithm']          as String;
          final dist  = (r['total_distance_km'] as num).toDouble();
          final ms    = (r['execution_time_ms'] as num).toDouble();
          final isWin = algo == winner;
          final color = algoColor(algo);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_algoLabel(algo),
                  style: TextStyle(fontSize: 12,
                      color: isWin ? AppColors.success : tp,
                      fontWeight: isWin ? FontWeight.w700 : FontWeight.w400))),
              Text('${dist.toStringAsFixed(2)} km  ·  ${ms.toStringAsFixed(1)} ms',
                  style: TextStyle(fontSize: 11, color: isWin ? AppColors.success : ts)),
            ]),
          );
        }),

        // AI yorumu
        if (aiInterp.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.07),
                  const Color(0xFF8B5CF6).withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(aiInterp,
                  style: TextStyle(color: tp, fontSize: 12, height: 1.4))),
            ]),
          ),
        ],
      ]),
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