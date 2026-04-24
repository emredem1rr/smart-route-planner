import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/constants/api_constants.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/background_task_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});
  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  // ── Static per-dataset state — persists across rebuilds ──────────
  static final Map<String, List<dynamic>> _dataResults  = {};
  static final Map<String, String>        _dataWinner   = {};
  static final Map<String, String?>       _dataError    = {};
  static final Map<String, bool>          _dataLoading  = {};
  static final Map<String, int>           _dataElapsed  = {};
  static final Map<String, int>           _dataCities   = {};
  static final Map<String, Timer?>        _dataTimers   = {};
  static bool _prefsLoaded = false;

  String _selectedDataset = 'berlin52';

  static const _datasetInfo = {
    'berlin52': {
      'label'   : 'Berlin52',
      'desc'    : '52 şehir · Optimal = 7.542',
      'n'       : 52,
      'optimal' : 7542,
      'endpoint': '/benchmark/berlin52',
    },
    'kroa100': {
      'label'   : 'kroA100',
      'desc'    : '100 şehir · Optimal = 21.282',
      'n'       : 100,
      'optimal' : 21282,
      'endpoint': '/benchmark/kroa100',
    },
    'pr76': {
      'label'   : 'pr76',
      'desc'    : '76 şehir · Optimal = 108.159',
      'n'       : 76,
      'optimal' : 108159,
      'endpoint': '/benchmark/pr76',
    },
  };

  static const _algoKeys = [
    'genetic', 'simulated_annealing', 'ant_colony', 'tabu_search', 'lin_kernighan'
  ];

  final Set<String> _selectedAlgos = {
    'genetic', 'simulated_annealing', 'ant_colony', 'tabu_search', 'lin_kernighan'
  };

  List<Map<String, dynamic>> _history = [];
  bool _showHistory = false;

  // ── Gerçek hayat sekmesi — per-scenario state ────────────
  static final Map<String, bool>    _rwLoading   = {};
  static final Map<String, String?> _rwError     = {};
  static final Map<String, dynamic> _rwResults   = {};  // key → scenario map

  // ── Özel dataset yükleme ──────────────────────────────────
  List<List<double>> _customCoords  = [];
  String             _customName    = '';
  bool               _customLoading = false;
  String?            _customError;
  List<dynamic>      _customResults = [];
  String             _customWinner  = '';
  int                _customCities  = 0;
  final _customOptCtrl  = TextEditingController();
  final _customNameCtrl = TextEditingController(text: 'Özel Dataset');

  // ── Şu an seçili datasetin state'i ───────────────────────
  List<dynamic> get _results  => _dataResults[_selectedDataset]  ?? [];
  String        get _winner   => _dataWinner[_selectedDataset]   ?? '';
  String?       get _error    => _dataError[_selectedDataset];
  bool          get _loading  => _dataLoading[_selectedDataset]  ?? false;
  int           get _elapsed  => _dataElapsed[_selectedDataset]  ?? 0;
  int           get _nCities  => _dataCities[_selectedDataset]   ?? 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    if (!_prefsLoaded) {
      _prefsLoaded = true;
      _loadAllFromPrefs();
      _loadRwFromPrefs();
    }
  }

  @override
  void dispose() {
    _customOptCtrl.dispose();
    _customNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final raw = await StorageService().getString('benchmark_history');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        if (mounted) setState(() => _history = list.cast<Map<String, dynamic>>());
      } catch (_) {}
    }
  }

  Future<void> _loadAllFromPrefs() async {
    for (final key in _datasetInfo.keys) {
      final raw = await StorageService().getString('bench_result_$key');
      if (raw != null && raw.isNotEmpty) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          _dataResults[key] = data['results'] as List;
          _dataWinner[key]  = data['winner']   as String? ?? '';
          _dataCities[key]  = data['n_cities'] as int;
          if (mounted) setState(() {});
        } catch (_) {}
      }
    }
  }

  Future<void> _saveResult(String key, Map<String, dynamic> json) async {
    await StorageService().setString('bench_result_$key', jsonEncode({
      'results' : json['results'],
      'winner'  : json['winner'],
      'n_cities': json['n_cities'],
    }));
  }

  Future<void> _saveToHistory(String key) async {
    final results = _dataResults[key] ?? [];
    final winner  = _dataWinner[key]  ?? '';
    final entry = {
      'date'    : DateTime.now().toIso8601String(),
      'dataset' : (_datasetInfo[key]!['label'] as String),
      'n_cities': _dataCities[key] ?? 0,
      'winner'  : winner,
      'results' : results.map((r) => {
        'algorithm'       : r['algorithm'],
        'tour_length'     : r['tour_length'],
        'gap_percent'     : r['gap_percent'],
        'execution_time_ms': r['execution_time_ms'],
      }).toList(),
    };
    _history.add(entry);
    if (_history.length > 10) _history = _history.sublist(_history.length - 10);
    await StorageService().setString('benchmark_history', jsonEncode(_history));
  }

  // ── TSP Klasik benchmark ──────────────────────────────────
  Future<void> _runBenchmark() async {
    final key = _selectedDataset;
    if (_dataLoading[key] == true) return;

    _dataLoading[key] = true;
    _dataError.remove(key);
    _dataResults.remove(key);
    _dataWinner.remove(key);
    _dataElapsed[key] = 0;

    _dataTimers[key]?.cancel();
    _dataTimers[key] = Timer.periodic(const Duration(seconds: 1), (_) {
      _dataElapsed[key] = (_dataElapsed[key] ?? 0) + 1;
      if (mounted && _selectedDataset == key) setState(() {});
    });

    if (mounted) setState(() {});

    final endpoint = _datasetInfo[key]!['endpoint'] as String;
    try {
      final response = await http
          .get(Uri.parse('${ApiConstants.optimizationBaseUrl}$endpoint'))
          .timeout(const Duration(seconds: 300));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] == true) {
        _dataResults[key] = json['results'] as List;
        _dataWinner[key]  = json['winner']   as String? ?? '';
        _dataCities[key]  = json['n_cities'] as int;
        _dataError.remove(key);
        await _saveResult(key, json);
        await _saveToHistory(key);
      } else {
        _dataError[key] = 'Benchmark başarısız: ${json['error'] ?? ''}';
      }
    } on SocketException {
      _dataError[key] = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.';
    } on TimeoutException {
      _dataError[key] = 'Bağlantı zaman aşımına uğradı.';
    } catch (e) {
      _dataError[key] = 'Hata oluştu.';
    } finally {
      _dataLoading[key] = false;
      _dataTimers[key]?.cancel();
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadRwFromPrefs() async {
    for (final key in ['kurye', 'satis', 'saglik']) {
      final raw = await StorageService().getString('rw_result_$key');
      if (raw != null && raw.isNotEmpty) {
        try {
          _rwResults[key] = jsonDecode(raw);
          if (mounted) setState(() {});
        } catch (_) {}
      }
    }
  }

  // ── Per-scenario Gerçek Hayat çalıştır ───────────────────
  Future<void> _runScenario(String scenarioKey) async {
    if (_rwLoading[scenarioKey] == true) return;
    final bgKey = 'rw_$scenarioKey';
    if (BackgroundTaskService().isRunning(bgKey)) return;

    _rwLoading[scenarioKey] = true;
    _rwError[scenarioKey]   = null;
    if (mounted) setState(() {});

    final url = '${ApiConstants.optimizationBaseUrl}/benchmark/real-world?scenario=$scenarioKey';
    BackgroundTaskService().run<Map<String, dynamic>?>(bgKey, () async {
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 300));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final scenarios = data['scenarios'] as List;
        if (scenarios.isNotEmpty) return scenarios.first as Map<String, dynamic>;
      }
      return null;
    }).then((sc) async {
      _rwLoading[scenarioKey] = false;
      BackgroundTaskService().clear(bgKey);
      if (sc != null) {
        _rwResults[scenarioKey] = sc;
        _rwError[scenarioKey]   = null;
        await StorageService().setString('rw_result_$scenarioKey', jsonEncode(sc));
      } else {
        _rwError[scenarioKey] = 'Senaryo başarısız oldu.';
      }
      if (mounted) setState(() {});
    });
  }

  // ── Özel dataset ──────────────────────────────────────────
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json', 'tsp', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file    = result.files.first;
      final content = utf8.decode(file.bytes ?? []);
      final name    = file.name;

      List<List<double>> coords = [];

      if (name.endsWith('.json')) {
        final data = jsonDecode(content);
        final raw  = data is Map ? (data['coordinates'] ?? data['coords'] ?? []) : data;
        coords = (raw as List).map<List<double>>((p) =>
            (p as List).map<double>((v) => (v as num).toDouble()).toList()
        ).toList();
        if (data is Map && data['optimal'] != null) {
          _customOptCtrl.text = data['optimal'].toString();
        }
        if (data is Map && data['name'] != null) {
          _customNameCtrl.text = data['name'].toString();
        }
      } else if (name.endsWith('.tsp')) {
        // TSPLIB formatı: NODE_COORD_SECTION sonrası "id x y" satırları
        bool inCoordSection = false;
        for (final rawLine in content.split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          if (line.toUpperCase() == 'NODE_COORD_SECTION') {
            inCoordSection = true;
            continue;
          }
          if (line.toUpperCase() == 'EOF' || line.toUpperCase().startsWith('DISPLAY_DATA_SECTION')) break;
          if (!inCoordSection) continue;
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final x = double.tryParse(parts[1]);
            final y = double.tryParse(parts[2]);
            if (x != null && y != null) coords.add([x, y]);
          }
        }
      } else {
        // CSV veya TXT: her satır "id,x,y" veya "x,y" veya "x y"
        for (final rawLine in content.split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final parts = line.contains(',')
              ? line.split(',')
              : line.split(RegExp(r'\s+'));
          // "id,x,y" formatı (3 sütun, ilki string/int id)
          if (parts.length >= 3) {
            final x = double.tryParse(parts[1].trim());
            final y = double.tryParse(parts[2].trim());
            if (x != null && y != null) { coords.add([x, y]); continue; }
          }
          // "x,y" formatı (2 sütun)
          if (parts.length >= 2) {
            final x = double.tryParse(parts[0].trim());
            final y = double.tryParse(parts[1].trim());
            if (x != null && y != null) coords.add([x, y]);
          }
        }
      }

      if (coords.length < 4) {
        if (mounted) setState(() => _customError = 'En az 4 koordinat gerekli. Yüklenen: ${coords.length}');
        return;
      }

      setState(() {
        _customCoords  = coords;
        _customError   = null;
        _customResults = [];
        _customWinner  = '';
        _customNameCtrl.text = name.replaceAll(RegExp(r'\.(csv|json|tsp|txt)$'), '');
      });
    } catch (e) {
      setState(() => _customError = 'Dosya okuma hatası: $e');
    }
  }

  Future<void> _runCustomBenchmark() async {
    if (_customCoords.isEmpty) {
      setState(() => _customError = 'Önce bir dataset dosyası yükleyin.');
      return;
    }
    final optimal = double.tryParse(_customOptCtrl.text.replaceAll(',', '.')) ?? -1.0;
    setState(() { _customLoading = true; _customError = null; _customResults = []; });
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.optimizationBaseUrl}/benchmark/custom'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'coordinates': _customCoords,
          'optimal'    : optimal,
          'name'       : _customNameCtrl.text.trim().isEmpty ? 'Özel Dataset' : _customNameCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 300));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() {
          _customResults = data['results'] as List;
          _customWinner  = data['winner']   as String? ?? '';
          _customCities  = data['n_cities'] as int;
        });
      } else {
        setState(() => _customError = 'Benchmark başarısız: ${data['error'] ?? ''}');
      }
    } on SocketException {
      setState(() => _customError = 'Sunucuya bağlanılamadı.');
    } catch (e) {
      setState(() => _customError = 'Hata oluştu.');
    } finally {
      setState(() => _customLoading = false);
    }
  }

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
              child: const Icon(Icons.science_rounded, color: Colors.white, size: 15),
            ),
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
                  Tab(icon: Icon(Icons.science_outlined,      size: 16), text: 'TSP Klasik'),
                  Tab(icon: Icon(Icons.location_city_rounded,  size: 16), text: 'Gerçek Hayat'),
                ],
              ),
            ]),
          ),
        ),
        body: TabBarView(
          children: [
            _buildClassicTab(surf, border, tp, ts),
            _buildRealWorldTab(surf, border, tp, ts),
          ],
        ),
      ),
    );
  }

  // ── TSP Klasik Sekmesi ────────────────────────────────────
  Widget _buildClassicTab(Color surf, Color border, Color tp, Color ts) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Geçmiş paneli
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
              child: Text('Temizle', style: TextStyle(fontSize: 12, color: AppColors.danger)),
            ),
          ]),
          const SizedBox(height: 8),
          ..._history.reversed.map((h) {
            final date    = DateTime.tryParse(h['date'] as String? ?? '');
            final dateStr = date != null
                ? '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
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
                            color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: results.map<Widget>((r) {
                  final gap = (r['gap_percent'] as num).toDouble();
                  final gc  = gap < 10 ? AppColors.success : gap < 25 ? AppColors.warn : AppColors.danger;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color:        gc.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border:       Border.all(color: gc.withOpacity(0.3)),
                    ),
                    child: Text('${_algoLabel(r['algorithm'] as String)}  %${gap.toStringAsFixed(1)}',
                        style: TextStyle(fontSize: 10, color: gc)),
                  );
                }).toList()),
              ]),
            );
          }),
          Divider(height: 24, color: border),
        ],

        // Dataset seçici
        Row(children: [
          Text('Dataset:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: tp)),
          const SizedBox(width: 10),
          ..._datasetInfo.entries.map((e) {
            final sel   = _selectedDataset == e.key;
            final label = e.value['label'] as String;
            final isRun = _dataResults.containsKey(e.key);
            return GestureDetector(
              onTap: () => setState(() => _selectedDataset = e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        sel ? AppColors.orange.withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? AppColors.orange : border,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: TextStyle(
                    fontSize: 12,
                    color:      sel ? AppColors.orange : ts,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                  )),
                  if (isRun) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 11),
                  ],
                ]),
              ),
            );
          }),
        ]),
        const SizedBox(height: 12),

        // Bilgi kartı
        Builder(builder: (_) {
          final info = _datasetInfo[_selectedDataset]!;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        AppColors.info.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: AppColors.info.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            ]),
          );
        }),
        const SizedBox(height: 14),

        // Başlat butonu
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
                        color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600),
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

        // Sonuç yok ama çalışmış seçili dataset
        if (_results.isEmpty && !_loading && _error == null && !_dataResults.containsKey(_selectedDataset)) ...[
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color:        AppColors.surfaceHigh(context),
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: border),
            ),
            child: Column(children: [
              Icon(Icons.pending_outlined, color: AppColors.textDim(context), size: 40),
              const SizedBox(height: 10),
              Text('Henüz çalıştırılmadı',
                  style: TextStyle(color: ts, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Benchmark Başlat butonuna basın.',
                  style: TextStyle(color: AppColors.textDim(context), fontSize: 12)),
            ]),
          ),
        ],

        // Sonuçlar
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
              child: Text(
                '${_datasetInfo[_selectedDataset]!['label']}  •  $_nCities şehir',
                style: TextStyle(color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 14),

          ..._results.asMap().entries.map((entry) {
            final r       = entry.value;
            final key     = r['algorithm'] as String;
            final gap     = (r['gap_percent'] as num).toDouble();
            final isWin   = key == _winner;
            final gapColor = gap < 10 ? AppColors.success : gap < 25 ? AppColors.warn : AppColors.danger;
            final ac = algoColor(key);
            final ai = algoIcon(key);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        AppColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isWin ? AppColors.success.withOpacity(0.5) : border,
                  width: isWin ? 1.5 : 1,
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          color: isWin ? AppColors.success : AppColors.textPrimary(context)))),
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
                  style: TextStyle(fontSize: 12, color: AppColors.textSecond(context)),
                ),
              ]),
            );
          }),

          // Grafik
          const SizedBox(height: 8),
          Row(children: [
            Text('Fitness Gelişimi',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                    color: AppColors.textPrimary(context))),
            const Spacer(),
            Text('Filtrele:', style: TextStyle(fontSize: 12, color: ts)),
          ]),
          const SizedBox(height: 8),
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
                    border: Border.all(color: selected ? color : border, width: selected ? 1.5 : 1),
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
                    Text(_algoLabel(key), style: TextStyle(
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
          Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: _buildChart(border, ts),
          ),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }

  // ── Gerçek Hayat Sekmesi ──────────────────────────────────
  Widget _buildRealWorldTab(Color surf, Color border, Color tp, Color ts) {
    const scenarios = [
      {'key': 'kurye',  'label': 'Kurye — Samsun, 10 durak',              'desc': 'Sabah 08:00\'de depodan başlayan teslimat rotası.'},
      {'key': 'satis',  'label': 'Satış Temsilcisi — Amasya, 7 durak',    'desc': 'Farklı öncelikte müşteri ziyaretleri, zaman pencereleri.'},
      {'key': 'saglik', 'label': 'Sağlık Ziyaretçisi — Amasya, 5 durak', 'desc': 'Kritik zaman pencereli hasta ziyaretleri.'},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Başlık
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:        const Color(0xFF6366F1).withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: const Color(0xFF6366F1).withOpacity(0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.location_city_rounded, color: Color(0xFF6366F1), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Her senaryo bağımsız çalışır. Ekrandan çıksan bile hesaplama durmaz.',
              style: TextStyle(color: ts, fontSize: 12, height: 1.4),
            )),
          ]),
        ),
        const SizedBox(height: 14),

        // Per-scenario kartlar
        ...scenarios.map((sc) {
          final key      = sc['key']!;
          final loading  = _rwLoading[key] == true || BackgroundTaskService().isRunning('rw_$key');
          final err      = _rwError[key];
          final result   = _rwResults[key];
          return _buildScenarioRunCard(key, sc['label']!, sc['desc']!, loading, err, result, surf, border, tp, ts);
        }),

        // ── Özel Dataset Yükleme ────────────────────────────
        const SizedBox(height: 24),
        Divider(color: border),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.upload_file_rounded, color: Color(0xFF6366F1), size: 18),
          const SizedBox(width: 8),
          Text('Özel Dataset Yükle (CSV / JSON / TSP)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tp)),
        ]),
        const SizedBox(height: 8),
        Text(
          'CSV: "id,x,y" veya "x,y" satırları.\n'
          'TSPLIB (.tsp): NODE_COORD_SECTION altında "id x y" formatı.\n'
          'JSON: {"coordinates":[[x,y],...], "optimal":12345, "name":"..."}',
          style: TextStyle(color: ts, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 4),
        Text(
          'TSPLIB örnek dosyalar: comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/',
          style: TextStyle(color: const Color(0xFF6366F1).withOpacity(0.8), fontSize: 11),
        ),
        const SizedBox(height: 12),

        // Dosya seç
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(
                _customCoords.isEmpty
                    ? 'Dosya Seç...'
                    : '${_customCoords.length} koordinat yüklendi',
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _customCoords.isEmpty ? AppColors.textSecond(context) : const Color(0xFF6366F1),
                side: BorderSide(color: _customCoords.isEmpty ? border : const Color(0xFF6366F1)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),

        if (_customCoords.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _customNameCtrl,
                style: TextStyle(color: tp, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Dataset Adı',
                  labelStyle: TextStyle(color: ts, fontSize: 12),
                  filled: true, fillColor: surf,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _customOptCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: tp, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Optimal Değer',
                  hintText: 'Bilinmiyorsa boş',
                  labelStyle: TextStyle(color: ts, fontSize: 12),
                  hintStyle: TextStyle(color: AppColors.textDim(context), fontSize: 11),
                  filled: true, fillColor: surf,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _customLoading ? null : _runCustomBenchmark,
              icon: _customLoading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.analytics_rounded, size: 20),
              label: Text(
                _customLoading ? 'Çalışıyor...' : 'Özel Dataset Çalıştır (${_customCoords.length} nokta)',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _customLoading ? AppColors.textDim(context) : const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding:   const EdgeInsets.symmetric(vertical: 13),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],

        if (_customError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:        AppColors.dangerDim,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AppColors.danger.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_customError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12))),
            ]),
          ),
        ],

        if (_customResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCustomResultCard(surf, border, tp, ts),
        ],

        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildCustomResultCard(Color surf, Color border, Color tp, Color ts) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_customNameCtrl.text.isNotEmpty ? _customNameCtrl.text : 'Özel Dataset',
                style: const TextStyle(color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text('$_customCities nokta', style: TextStyle(color: ts, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        if (_customWinner.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            margin:  const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color:        AppColors.success.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.emoji_events_rounded, color: AppColors.success, size: 16),
              const SizedBox(width: 8),
              Text('Kazanan: ${_algoLabel(_customWinner)}',
                  style: const TextStyle(color: AppColors.success,
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ..._customResults.map((r) {
          final algo  = r['algorithm'] as String;
          final tour  = (r['tour_length'] as num).toDouble();
          final gap   = (r['gap_percent'] as num).toDouble();
          final ms    = (r['execution_time_ms'] as num).toDouble();
          final isWin = algo == _customWinner;
          final color = algoColor(algo);
          final gapColor = gap < 10 ? AppColors.success : gap < 25 ? AppColors.warn : AppColors.danger;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(_algoLabel(algo),
                  style: TextStyle(fontSize: 12,
                      color: isWin ? AppColors.success : tp,
                      fontWeight: isWin ? FontWeight.w700 : FontWeight.w400))),
              Text('${tour.toStringAsFixed(1)}', style: TextStyle(fontSize: 11, color: ts)),
              const SizedBox(width: 8),
              if (gap >= 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: gapColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('%${gap.toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 10, color: gapColor, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(width: 6),
              Text('${ms.toStringAsFixed(1)} ms', style: TextStyle(fontSize: 10, color: ts)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildScenarioRunCard(
    String key, String label, String desc,
    bool loading, String? err, dynamic result,
    Color surf, Color border, Color tp, Color ts,
  ) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: tp))),
          GestureDetector(
            onTap: loading ? null : () => _runScenario(key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: loading ? null : const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                color: loading ? AppColors.border(context) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (loading)
                  const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(loading ? 'Çalışıyor...' : (result != null ? 'Yenile' : 'Çalıştır'),
                    style: const TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(color: ts, fontSize: 11)),

        if (loading) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                minHeight: 3, backgroundColor: border,
                color: const Color(0xFF6366F1)),
          ),
        ],

        if (err != null) ...[
          const SizedBox(height: 8),
          Text(err, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        ],

        if (result != null) ...[
          const SizedBox(height: 10),
          _buildScenarioCard(result, surf, border, tp, ts),
        ],
      ]),
    );
  }

  Widget _buildScenarioCard(dynamic sc, Color surf, Color border, Color tp, Color ts) {
    final winner     = sc['winner']              as String;
    final winnerDist = (sc['winner_distance_km'] as num).toDouble();
    final aiInterp   = sc['ai_interpretation']   as String? ?? '';
    final results    = (sc['results'] as List).cast<Map<String, dynamic>>();
    final manualDist = sc['manual_distance_km'] != null
        ? (sc['manual_distance_km'] as num).toDouble() : 0.0;
    final improvPct  = sc['improvement_vs_manual_pct'] != null
        ? (sc['improvement_vs_manual_pct'] as num).toDouble() : 0.0;
    final kmSaved    = sc['km_saved'] != null
        ? (sc['km_saved'] as num).toDouble() : 0.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Kazanan
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
      const SizedBox(height: 8),

      // Tablo: Algoritma | Mesafe | Gap%best | Manuel'e göre %
      ...results.map((r) {
        final algo    = r['algorithm']          as String;
        final dist    = (r['total_distance_km'] as num).toDouble();
        final gapBest = r['gap_vs_best'] != null ? (r['gap_vs_best'] as num).toDouble() : 0.0;
        final gapMan  = r['gap_vs_manual'] != null ? (r['gap_vs_manual'] as num).toDouble() : 0.0;
        final isWin   = algo == winner;
        final color   = algoColor(algo);
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color:        isWin ? AppColors.success.withOpacity(0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:       isWin ? Border.all(color: AppColors.success.withOpacity(0.4)) : null,
          ),
          child: Row(children: [
            Container(width: 7, height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(_algoLabel(algo),
                style: TextStyle(fontSize: 11,
                    color: isWin ? AppColors.success : tp,
                    fontWeight: isWin ? FontWeight.w700 : FontWeight.w400))),
            Text('${dist.toStringAsFixed(2)} km',
                style: TextStyle(fontSize: 10, color: isWin ? AppColors.success : ts)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: (gapBest < 5 ? AppColors.success : gapBest < 15 ? AppColors.warn : AppColors.danger).withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                isWin ? 'En iyi' : '+${gapBest.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600,
                  color: isWin ? AppColors.success : gapBest < 15 ? AppColors.warn : AppColors.danger,
                ),
              ),
            ),
            if (!isWin && gapMan > 0) ...[
              const SizedBox(width: 4),
              Text('-${gapMan.toStringAsFixed(1)}% manuel',
                  style: TextStyle(fontSize: 9, color: AppColors.info)),
            ],
          ]),
        );
      }),

      // Tasarruf banner
      if (improvPct > 0 && kmSaved > 0) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Manuel plana göre %${improvPct.toStringAsFixed(1)} tasarruf  ·  ${kmSaved.toStringAsFixed(1)} km kazanç',
            style: const TextStyle(color: AppColors.success,
                fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],

      if (aiInterp.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              const Color(0xFF6366F1).withOpacity(0.07),
              const Color(0xFF8B5CF6).withOpacity(0.04),
            ]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 14),
            const SizedBox(width: 8),
            Expanded(child: Text(aiInterp,
                style: TextStyle(color: tp, fontSize: 12, height: 1.4))),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildChart(Color border, Color ts) {
    if (_results.isEmpty) return const SizedBox();

    final lines    = <LineChartBarData>[];
    double globalMin = double.infinity;
    double globalMax = double.negativeInfinity;

    for (final r in _results) {
      final key = r['algorithm'] as String;
      if (!_selectedAlgos.contains(key)) continue;
      final history = (r['fitness_history'] as List)
          .map((v) => (v as num).toDouble()).toList();
      if (history.isEmpty) continue;
      final mn = history.reduce((a, b) => a < b ? a : b);
      final mx = history.reduce((a, b) => a > b ? a : b);
      if (mn < globalMin) globalMin = mn;
      if (mx > globalMax) globalMax = mx;
    }

    if (globalMin == double.infinity) return const SizedBox();

    final yPadding = (globalMax - globalMin) * 0.1;
    final yMin     = globalMin - yPadding;
    final yMax     = globalMax + yPadding;

    for (final r in _results) {
      final key = r['algorithm'] as String;
      if (!_selectedAlgos.contains(key)) continue;
      final history = (r['fitness_history'] as List)
          .map((v) => (v as num).toDouble()).toList();
      if (history.isEmpty) continue;

      lines.add(LineChartBarData(
        spots: history.asMap().entries
            .map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
        isCurved:     true,
        color:        algoColor(key),
        barWidth:     2,
        dotData:      const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

    return LineChart(LineChartData(
      minY:         yMin,
      maxY:         yMax,
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
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(2),
                style: TextStyle(fontSize: 7, color: ts)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) => Text('${v.toInt()}',
                style: TextStyle(fontSize: 8, color: ts)),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
    ));
  }
}
