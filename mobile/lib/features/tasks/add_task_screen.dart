import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import '../../core/models/task_model.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../suggest/map_picker_screen.dart';

class AddTaskScreen extends StatefulWidget {
  final int taskId;
  const AddTaskScreen({super.key, required this.taskId});
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen>
    with SingleTickerProviderStateMixin {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _durCtrl     = TextEditingController();
  final _parseCtrl   = TextEditingController();
  final _noteCtrl    = TextEditingController();
  final GeocodingService _geocodingService = GeocodingService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  late TabController _tabCtrl;

  int        _priority         = 3;
  double?    _latitude;
  double?    _longitude;
  bool       _geocodingLoading = false;
  String     _coordinateText   = '';
  TimeOfDay? _earliestStart;
  late DateTime _selectedDate;
  bool       _isRecurring      = false;
  String     _recurrenceType   = 'daily';
  List<int>  _selectedDays     = [];
  bool       _listening        = false;
  bool       _parsing          = false;
  bool       _speechAvailable  = false;

  // Harita
  final MapController _mapCtrl = MapController();
  LatLng? _markerPos;
  final _mapSearchCtrl = TextEditingController();
  bool _mapSearchLoading = false;

  static const _dayNames = {
    1: 'Pzt', 2: 'Sal', 3: 'Çar',
    4: 'Per', 5: 'Cum', 6: 'Cmt', 7: 'Paz',
  };

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _tabCtrl = TabController(length: 2, vsync: this);
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) => print('[Speech] hata: $e'),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _addressCtrl.dispose();
    _durCtrl.dispose(); _parseCtrl.dispose();
    _noteCtrl.dispose();
    _mapSearchCtrl.dispose(); _tabCtrl.dispose();
    super.dispose();
  }

  // ── Tarih/saat yardımcıları ───────────────────────────────
  String _formattedDate(String Function(String) t) {
    final now = DateTime.now();
    if (_selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day) return 'Bugün';
    final tmrw = now.add(const Duration(days: 1));
    if (_selectedDate.year == tmrw.year &&
        _selectedDate.month == tmrw.month &&
        _selectedDate.day == tmrw.day) return 'Yarın';
    return '${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}';
  }

  String get _taskDateString =>
      '${_selectedDate.year}-'
          '${_selectedDate.month.toString().padLeft(2, '0')}-'
          '${_selectedDate.day.toString().padLeft(2, '0')}';

  String get _timeString => _earliestStart != null
      ? '${_earliestStart!.hour.toString().padLeft(2, '0')}:'
      '${_earliestStart!.minute.toString().padLeft(2, '0')}'
      : 'Belirtilmedi';

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate:   DateTime.now(),
      lastDate:    DateTime.now().add(const Duration(days: 365)),
      locale:      const Locale('tr', 'TR'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary:   AppColors.orange,
            onPrimary: Colors.white,
            surface:   AppColors.surface(ctx),
            onSurface: AppColors.textPrimary(ctx),
          ),
        ),
        child: child!,
      ),
    );
    if (p != null) setState(() => _selectedDate = p);
  }

  Future<void> _pickTime() async {
    final p = await showTimePicker(
      context:     context,
      initialTime: _earliestStart ?? TimeOfDay.now(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (p != null) setState(() => _earliestStart = p);
  }

  // ── Adres geocode ─────────────────────────────────────────
  Future<void> _geocodeAddress() async {
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty) return;
    setState(() { _geocodingLoading = true; _coordinateText = 'Koordinatlar aranıyor...'; });
    final r = await _geocodingService.addressToCoordinates(addr);
    setState(() => _geocodingLoading = false);
    if (r != null) {
      setState(() {
        _latitude       = r['latitude'];
        _longitude      = r['longitude'];
        _coordinateText = r['formatted_address'] ??
            'Enlem: ${_latitude!.toStringAsFixed(5)}, Boylam: ${_longitude!.toStringAsFixed(5)}';
        _markerPos = LatLng(_latitude!, _longitude!);
      });
    } else {
      setState(() { _latitude = null; _longitude = null; _coordinateText = 'Konum bulunamadı.'; });
    }
  }

  // ── Harita arama ──────────────────────────────────────────
  Future<void> _searchOnMap() async {
    final q = _mapSearchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _mapSearchLoading = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&format=json&limit=1',
      );
      final resp = await http.get(url, headers: {'User-Agent': 'SmartRoutePlanner/1.0'});
      final list = jsonDecode(resp.body) as List;
      if (list.isNotEmpty) {
        final lat = double.parse(list[0]['lat']);
        final lon = double.parse(list[0]['lon']);
        final displayName = list[0]['display_name'] as String;
        setState(() {
          _markerPos      = LatLng(lat, lon);
          _latitude       = lat;
          _longitude      = lon;
          _coordinateText = displayName;
          _addressCtrl.text = displayName.split(',').take(2).join(',').trim();
        });
        _mapCtrl.move(LatLng(lat, lon), 15);
      } else {
        _snack('Konum bulunamadı');
      }
    } catch (e) {
      _snack('Arama hatası: $e');
    }
    setState(() => _mapSearchLoading = false);
  }

  // ── Sesli/yazı parse ──────────────────────────────────────
  Future<void> _startListening() async {
    if (!_speechAvailable) {
      _snack('Mikrofon kullanılamıyor', color: AppColors.danger);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        setState(() => _parseCtrl.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          _parseText(_parseCtrl.text);
        }
      },
      localeId:         'tr_TR',
      listenMode:       stt.ListenMode.dictation,
      cancelOnError:    true,
      partialResults:   true,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  Future<void> _parseText(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _parsing = true);
    try {
      final parsed = _parseLocally(text);
      _applyParsed(parsed);
      // Eksik alanları kullanıcıya sor
      await _askMissing(parsed);
    } finally {
      setState(() => _parsing = false);
    }
  }

  Map<String, dynamic> _parseLocally(String text) {
    final result = <String, dynamic>{};
    final lower  = text.toLowerCase();

    // ── Görev adı — ilk anlamlı kelimeler ────────────────
    result['name'] = text.trim();

    // ── Tarih parse ───────────────────────────────────────
    final now = DateTime.now();

    if (lower.contains('bugün')) {
      result['date'] = now;
    } else if (lower.contains('yarın')) {
      result['date'] = now.add(const Duration(days: 1));
    } else if (lower.contains('öbür gün') || lower.contains('öbürgün')) {
      result['date'] = now.add(const Duration(days: 2));
    } else {
      // "ayın 18i" veya "18inde" veya "18'inde"
      final dayRegex = RegExp(r"ayin?\s*(\d{1,2})");
      final dayMatch = dayRegex.firstMatch(lower);
      if (dayMatch != null) {
        final day = int.tryParse(dayMatch.group(1)!);
        if (day != null) {
          var d = DateTime(now.year, now.month, day);
          if (d.isBefore(now)) d = DateTime(now.year, now.month + 1, day);
          result['date'] = d;
        }
      }

      // "kasım ayının 14ünde" / "kasım 14" / "14 kasım"
      final months = {
        'ocak':1,'şubat':2,'mart':3,'nisan':4,'mayıs':5,'haziran':6,
        'temmuz':7,'ağustos':8,'eylül':9,'ekim':10,'kasım':11,'aralık':12,
      };
      for (final entry in months.entries) {
        if (lower.contains(entry.key)) {
          final numRegex = RegExp(r'(\d{1,2})');
          final matches  = numRegex.allMatches(lower).toList();
          // Ayın adından önce veya sonraki sayıyı al
          int? day;
          for (final m in matches) {
            final n = int.tryParse(m.group(1)!);
            if (n != null && n >= 1 && n <= 31) { day = n; break; }
          }
          if (day != null) {
            var d = DateTime(now.year, entry.value, day);
            if (d.isBefore(now)) d = DateTime(now.year + 1, entry.value, day);
            result['date'] = d;
          }
          break;
        }
      }

      // "pazartesi", "salı" vb.
      final weekdays = {
        'pazartesi':1,'salı':2,'çarşamba':3,'perşembe':4,
        'cuma':5,'cumartesi':6,'pazar':7,
      };
      for (final entry in weekdays.entries) {
        if (lower.contains(entry.key)) {
          var d = now;
          while (d.weekday != entry.value) d = d.add(const Duration(days: 1));
          if (d == now) d = d.add(const Duration(days: 7));
          result['date'] = d;
          break;
        }
      }
    }

    // ── Saat parse ────────────────────────────────────────
    // "saat 14", "14:30", "3'te", "15 te", "öğleden sonra 3"
    final timeRegex = RegExp(r'(\d{1,2})[:\.](\d{2})');
    final timeMatch = timeRegex.firstMatch(lower);
    if (timeMatch != null) {
      result['hour']   = int.parse(timeMatch.group(1)!);
      result['minute'] = int.parse(timeMatch.group(2)!);
    } else {
      final hourRegex = RegExp(r"saat\s+(\d{1,2})|(\d{1,2})\s*te\b|(\d{1,2})\s*da\b|(\d{1,2})\s*de\b");
      final hourMatch = hourRegex.firstMatch(lower);
      if (hourMatch != null) {
        final h = int.tryParse(
            hourMatch.group(1) ?? hourMatch.group(2) ??
                hourMatch.group(3) ?? hourMatch.group(4) ?? '');
        if (h != null) {
          result['hour']   = h;
          result['minute'] = 0;
        }
      }
    }

    // Öğleden sonra/akşam için 12 ekle
    if (result.containsKey('hour')) {
      final h = result['hour'] as int;
      if (h < 12 && (lower.contains('öğleden sonra') ||
          lower.contains('akşam') || lower.contains('gece'))) {
        result['hour'] = h + 12;
      }
    }

    // ── Süre parse ────────────────────────────────────────
    final durRegex = RegExp(r'(\d+)\s*(?:dakika|dk|saat)');
    final durMatch = durRegex.firstMatch(lower);
    if (durMatch != null) {
      var dur = int.parse(durMatch.group(1)!);
      if (lower.contains('saat') && !lower.contains('dakika')) dur *= 60;
      result['duration'] = dur;
    }

    return result;
  }

  void _applyParsed(Map<String, dynamic> parsed) {
    if (parsed['name'] != null) _nameCtrl.text = parsed['name'];
    if (parsed['date'] != null) _selectedDate = parsed['date'] as DateTime;
    if (parsed['hour'] != null) {
      _earliestStart = TimeOfDay(
        hour:   parsed['hour'] as int,
        minute: parsed['minute'] as int? ?? 0,
      );
    }
    if (parsed['duration'] != null) {
      _durCtrl.text = '${parsed['duration']}';
    }
    setState(() {});
  }

  // Eksik alanları sırayla sor
  Future<void> _askMissing(Map<String, dynamic> parsed) async {
    // Süre yoksa sor
    if (_durCtrl.text.isEmpty) {
      final dur = await _showDurationPicker();
      if (dur != null) setState(() => _durCtrl.text = '$dur');
    }
    // Öncelik varsayılan 3 — değiştirmek isterse manuel yapabilir
    // Konum yoksa haritayı aç
    if (_latitude == null) {
      _tabCtrl.animateTo(1);
      _snack('Lütfen haritadan konumu seçin', color: AppColors.orange);
    }
  }

  Future<int?> _showDurationPicker() async {
    int? selected = 30;
    return await showDialog<int>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface(context),
          title: Text('Ziyaret Süresi',
              style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700)),
          content: Wrap(
            spacing: 8, runSpacing: 8,
            children: [15, 30, 45, 60, 90, 120].map((m) {
              final sel = selected == m;
              final label = m < 60 ? '$m dk' : m == 60 ? '1 saat' : '${m~/60} saat';
              return GestureDetector(
                onTap: () => setD(() => selected = m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color:        sel ? AppColors.orange.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppColors.orange : AppColors.border(context),
                        width: sel ? 1.5 : 1),
                  ),
                  child: Text(label, style: TextStyle(
                    color:      sel ? AppColors.orange : AppColors.textSecond(context),
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                  )),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Atla', style: TextStyle(color: AppColors.textSecond(context))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selected),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange, foregroundColor: Colors.white),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: color ?? AppColors.danger,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Kaydet ────────────────────────────────────────────────
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      _snack('Lütfen haritadan veya adres alanından konum seçin');
      return;
    }
    final duration = int.parse(_durCtrl.text.trim());
    final es       = _earliestStart != null ? _toMinutes(_earliestStart!) : 0;
    final lf       = _earliestStart != null ? es + duration : 1440;

    final task = TaskModel(
      id:             widget.taskId,
      name:           _nameCtrl.text.trim(),
      address:        _addressCtrl.text.trim(),
      latitude:       _latitude!,
      longitude:      _longitude!,
      duration:       duration,
      priority:       _priority,
      earliestStart:  es,
      latestFinish:   lf,
      taskDate:       _taskDateString,
      isRecurring:    _isRecurring,
      recurrenceType: _isRecurring ? _recurrenceType : null,
      recurrenceDays: _isRecurring && _recurrenceType == 'weekly'
          ? _selectedDays.join(',') : null,
      note:           _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    Navigator.pop(context, task);
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
        toolbarHeight:    85,
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
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.add_task_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Text('Görev Ekle', style: TextStyle(color: tp, fontSize: 15,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border))),
            child: TabBar(
              controller: _tabCtrl,
              labelColor:           const Color(0xFF6366F1),
              unselectedLabelColor: ts,
              indicatorColor:       const Color(0xFF6366F1),
              indicatorWeight:      2,
              indicatorSize:        TabBarIndicatorSize.label,
              tabs: const [
                Tab(icon: Icon(Icons.edit_note_rounded, size: 19), text: 'Form'),
                Tab(icon: Icon(Icons.map_outlined,       size: 19), text: 'Harita'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildFormTab(bg, surf, border, tp, ts, t),
          _buildMapTab(surf, border, tp, ts),
        ],
      ),
    );
  }

  // ── Form Tab ──────────────────────────────────────────────
  Widget _buildFormTab(Color bg, Color surf, Color border, Color tp, Color ts,
      String Function(String) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Hızlı Şablonlar ──────────────────────────────
          _SectionLabel(text: 'Hızlı Şablonlar', color: ts),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _templateChip('🏥 Eczane',    'Eczane',         30, surf, border, ts),
              const SizedBox(width: 8),
              _templateChip('🛒 Market',    'Market Alışverişi', 45, surf, border, ts),
              const SizedBox(width: 8),
              _templateChip('🏦 Banka',     'Banka',          30, surf, border, ts),
              const SizedBox(width: 8),
              _templateChip('👨‍⚕️ Doktor',   'Doktor Randevusu', 60, surf, border, ts),
              const SizedBox(width: 8),
              _templateChip('🏫 Okul',      'Okul',           30, surf, border, ts),
              const SizedBox(width: 8),
              _templateChip('⛽ Benzin',    'Benzin',         15, surf, border, ts),
              const SizedBox(width: 8),
              _templateChip('📦 Kargo',     'Kargo Teslim',   20, surf, border, ts),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Sesli / Yazı ile hızlı giriş ─────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.orange.withOpacity(0.08),
                  AppColors.orange.withOpacity(0.04)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.orange.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome, color: AppColors.orange, size: 16),
                const SizedBox(width: 6),
                Text('Hızlı Giriş',
                    style: TextStyle(color: AppColors.orange,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Text('örn: "Yarın saat 3te Migros"',
                    style: TextStyle(color: ts, fontSize: 11)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _parseCtrl,
                    style: TextStyle(color: tp, fontSize: 13),
                    decoration: InputDecoration(
                      hintText:  'Görev açıkla veya sesle söyle...',
                      hintStyle: TextStyle(color: ts, fontSize: 12),
                      filled:    true,
                      fillColor: surf,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border:        OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:   BorderSide(color: border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:   BorderSide(color: border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:   const BorderSide(
                              color: AppColors.orange, width: 1.5)),
                    ),
                    onSubmitted: _parseText,
                  ),
                ),
                const SizedBox(width: 8),
                // Sesli giriş butonu
                GestureDetector(
                  onTap: _listening ? _stopListening : _startListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color:        _listening
                          ? AppColors.danger
                          : AppColors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _listening ? Icons.stop : Icons.mic_rounded,
                      color: Colors.white, size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Parse butonu
                GestureDetector(
                  onTap: _parsing ? null : () => _parseText(_parseCtrl.text),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color:        AppColors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.orange.withOpacity(0.4)),
                    ),
                    child: _parsing
                        ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.orange))
                        : const Icon(Icons.auto_fix_high_rounded,
                        color: AppColors.orange, size: 20),
                  ),
                ),
              ]),
              if (_parsing) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 4),
                  SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.orange)),
                  const SizedBox(width: 8),
                  Text('Analiz ediliyor...',
                      style: TextStyle(color: ts, fontSize: 12)),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 20),

          // ── Görev Adı ─────────────────────────────────────
          _SectionLabel(text: 'Görev Adı', color: ts),
          const SizedBox(height: 8),
          _buildField(
            controller: _nameCtrl, hintText: 'Görev adını giriniz..',
            prefixIcon: Icons.task_alt_outlined,
            surf: surf, border: border, tp: tp, ts: ts,
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
          ),
          const SizedBox(height: 20),

          // ── Adres ─────────────────────────────────────────
          _SectionLabel(text: 'Adres', color: ts),
          const SizedBox(height: 8),
          _buildField(
            controller: _addressCtrl, hintText: 'Adres giriniz..',
            prefixIcon: Icons.place_outlined,
            onEditingComplete: _geocodeAddress,
            surf: surf, border: border, tp: tp, ts: ts,
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
            suffixIcon: _geocodingLoading
                ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.orange)))
                : IconButton(
              icon: Icon(Icons.search_rounded,
                  color: AppColors.orange, size: 20),
              onPressed: _geocodeAddress,
            ),
          ),
          const SizedBox(height: 8),
          // Haritadan konum seç butonu
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push<MapPickerResult>(context,
                  MaterialPageRoute(builder: (_) => MapPickerScreen(
                    initialLat: _latitude,
                    initialLng: _longitude,
                  )));
              if (result != null && mounted) {
                setState(() {
                  _addressCtrl.text = result.address.split(',').take(3).join(',').trim();
                  _latitude         = result.latitude;
                  _longitude        = result.longitude;
                  _coordinateText   = 'Enlem: ${result.latitude.toStringAsFixed(5)}, '
                      'Boylam: ${result.longitude.toStringAsFixed(5)}';
                  _markerPos = LatLng(result.latitude, result.longitude);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:        AppColors.orangeDim,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppColors.orange.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.map_rounded, color: AppColors.orange, size: 16),
                const SizedBox(width: 8),
                Text(
                  _latitude != null ? 'Konumu Değiştir (Haritadan)' : 'Haritadan Konum Seç',
                  style: const TextStyle(color: AppColors.orange,
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios, color: AppColors.orange, size: 12),
              ]),
            ),
          ),
          if (_coordinateText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(
                _latitude != null
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 13,
                color: _latitude != null ? AppColors.success : ts,
              ),
              const SizedBox(width: 5),
              Expanded(child: Text(_coordinateText,
                  style: TextStyle(fontSize: 12,
                      color: _latitude != null ? AppColors.success : ts))),
            ]),
          ],
          // Haritadan seç butonu
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _tabCtrl.animateTo(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:        const Color(0xFF3D9CF5).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF3D9CF5).withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.map_outlined,
                    color: Color(0xFF3D9CF5), size: 14),
                const SizedBox(width: 6),
                Text('Haritadan seç',
                    style: const TextStyle(
                        color: Color(0xFF3D9CF5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Süre ──────────────────────────────────────────
          _SectionLabel(text: 'Ziyaret Süresi (dakika)', color: ts),
          const SizedBox(height: 8),
          _buildField(
            controller: _durCtrl, hintText: 'örn: 30',
            prefixIcon: Icons.timer_outlined,
            keyboardType: TextInputType.number,
            surf: surf, border: border, tp: tp, ts: ts,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Zorunlu alan';
              final i = int.tryParse(v.trim());
              if (i == null || i < 1) return 'En az 1 dakika';
              return null;
            },
          ),
          const SizedBox(height: 8),
          // Hızlı süre seçici
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [15, 30, 60, 90, 120].map((m) {
              final label = m < 60 ? '$m dk' : m == 60 ? '1 sa' : '${m~/60} sa';
              final sel   = _durCtrl.text == '$m';
              return GestureDetector(
                onTap: () => setState(() => _durCtrl.text = '$m'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:        sel ? AppColors.orange.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: sel ? AppColors.orange : border,
                        width: sel ? 1.5 : 1),
                  ),
                  child: Text(label, style: TextStyle(
                    fontSize:   12,
                    color:      sel ? AppColors.orange : ts,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                  )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Öncelik ───────────────────────────────────────
          _SectionLabel(text: 'Öncelik', color: ts),
          const SizedBox(height: 10),
          _buildPrioritySelector(surf, border, ts),
          const SizedBox(height: 20),

          // ── Tarih & Saat ──────────────────────────────────
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionLabel(text: 'Görev Tarihi', color: ts),
              const SizedBox(height: 8),
              _PickerTile(
                icon: Icons.calendar_today_outlined,
                label: _formattedDate(t),
                onTap: _pickDate,
                surf: surf, border: border, tp: tp, ts: ts,
              ),
            ],
            )),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionLabel(text: 'Başlama Saati', color: ts),
              const SizedBox(height: 8),
              Stack(children: [
                _PickerTile(
                  icon: Icons.access_time_outlined,
                  label: _timeString,
                  onTap: _pickTime,
                  surf: surf, border: border, tp: tp, ts: ts,
                ),
                if (_earliestStart != null)
                  Positioned(right: 0, top: 0, bottom: 0,
                      child: IconButton(
                        icon: Icon(Icons.clear, size: 15, color: ts),
                        onPressed: () => setState(() => _earliestStart = null),
                      )),
              ]),
            ],
            )),
          ]),
          const SizedBox(height: 20),

          // ── Tekrarlayan görev ─────────────────────────────
          _SectionLabel(text: 'Yineleme', color: ts),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surf, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text('Tekrarlayan Görev',
                  style: TextStyle(color: tp, fontSize: 14,
                      fontWeight: FontWeight.w500)),
              subtitle: Text('Her gün, hafta içi veya belirli günler',
                  style: TextStyle(color: ts, fontSize: 12)),
              value: _isRecurring,
              activeColor: AppColors.orange,
              onChanged: (v) => setState(() => _isRecurring = v),
            ),
          ),
          if (_isRecurring) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                backgroundColor:        surf,
                selectedBackgroundColor: AppColors.orange.withOpacity(0.12),
                selectedForegroundColor: AppColors.orange,
                foregroundColor:         ts,
                side: BorderSide(color: border),
              ),
              segments: const [
                ButtonSegment(value: 'daily',    label: Text('Her Gün')),
                ButtonSegment(value: 'weekdays', label: Text('Hafta İçi')),
                ButtonSegment(value: 'weekly',   label: Text('Haftalık')),
              ],
              selected:           {_recurrenceType},
              onSelectionChanged: (s) =>
                  setState(() => _recurrenceType = s.first),
            ),
            if (_recurrenceType == 'weekly') ...[
              const SizedBox(height: 12),
              Text('Hangi günler?',
                  style: TextStyle(fontSize: 13, color: ts)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _dayNames.entries.map((e) {
                  final sel = _selectedDays.contains(e.key);
                  return GestureDetector(
                    onTap: () => setState(() => sel
                        ? _selectedDays.remove(e.key)
                        : _selectedDays.add(e.key)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.orange.withOpacity(0.12) : surf,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: sel ? AppColors.orange : border,
                            width: sel ? 1.5 : 1),
                      ),
                      child: Text(e.value, style: TextStyle(
                        color: sel ? AppColors.orange : ts,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 13,
                      )),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
          const SizedBox(height: 32),

          // ── Not ───────────────────────────────────────────────
          _SectionLabel(text: 'Not (opsiyonel)', color: ts),
          const SizedBox(height: 8),
          TextField(
            controller:  _noteCtrl,
            maxLines:    3,
            maxLength:   200,
            style: TextStyle(color: tp, fontSize: 14),
            decoration: InputDecoration(
              hintText:       'Hatırlatıcı not ekle...',
              hintStyle:      TextStyle(color: ts, fontSize: 13),
              filled:         true,
              fillColor:      surf,
              counterStyle:   TextStyle(color: ts, fontSize: 11),
              contentPadding: const EdgeInsets.all(14),
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Kaydet butonu ─────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon:  const Icon(Icons.check_rounded, size: 18),
              label: const Text('Görevi Ekle',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding:   const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ── Harita Tab ────────────────────────────────────────────
  Widget _buildMapTab(Color surf, Color border, Color tp, Color ts) {
    final center = _markerPos ?? const LatLng(39.9208, 32.8541); // Ankara

    return Column(children: [
      // Harita arama kutusu
      Container(
        color: surf,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _mapSearchCtrl,
              style: TextStyle(color: tp, fontSize: 13),
              decoration: InputDecoration(
                hintText:  'Konum ara — "Migros Amasya"',
                hintStyle: TextStyle(color: ts, fontSize: 12),
                prefixIcon: Icon(Icons.search, color: ts, size: 18),
                filled: true, fillColor: AppColors.bg(context),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border:        OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:   BorderSide(color: border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:   BorderSide(color: border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:   const BorderSide(
                        color: AppColors.orange, width: 1.5)),
              ),
              onSubmitted: (_) => _searchOnMap(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _mapSearchLoading ? null : _searchOnMap,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(10)),
              child: _mapSearchLoading
                  ? const Padding(padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
      // Bilgi satırı
      Container(
        color: AppColors.bg(context),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(Icons.touch_app_outlined, size: 13, color: ts),
          const SizedBox(width: 6),
          Text('Haritaya tıkla veya basılı tut — pin koy',
              style: TextStyle(fontSize: 11, color: ts)),
          if (_markerPos != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: () => _tabCtrl.animateTo(0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color:        AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('✓ Konum Seçildi',
                    style: TextStyle(fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
      ),
      // Harita
      Expanded(
        child: FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: center,
            initialZoom:   13,
            onTap: (_, latlng) => _setMapMarker(latlng),
            onLongPress: (_, latlng) => _setMapMarker(latlng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.mobile',
            ),
            if (_markerPos != null)
              MarkerLayer(markers: [
                Marker(
                  point:  _markerPos!,
                  width:  48,
                  height: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color:        AppColors.orange,
                          shape:        BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color:       AppColors.orange.withOpacity(0.4),
                            blurRadius:  8,
                            spreadRadius: 2,
                          )],
                        ),
                        child: const Icon(Icons.place_rounded,
                            color: Colors.white, size: 20),
                      ),
                      Container(
                        width: 2, height: 10,
                        color: AppColors.orange,
                      ),
                    ],
                  ),
                ),
              ]),
          ],
        ),
      ),
    ]);
  }

  Future<void> _setMapMarker(LatLng pos) async {
    setState(() {
      _markerPos = pos;
      _latitude  = pos.latitude;
      _longitude = pos.longitude;
      _coordinateText = '${pos.latitude.toStringAsFixed(5)}, '
          '${pos.longitude.toStringAsFixed(5)}';
    });
    // Reverse geocode
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}'
            '&lon=${pos.longitude}&format=json',
      );
      final resp = await http.get(url,
          headers: {'User-Agent': 'SmartRoutePlanner/1.0'});
      final data = jsonDecode(resp.body);
      if (data['display_name'] != null) {
        final addr = data['display_name'] as String;
        setState(() {
          _coordinateText = addr;
          if (_addressCtrl.text.isEmpty) {
            _addressCtrl.text = addr.split(',').take(2).join(',').trim();
          }
        });
      }
    } catch (_) {}
  }

  Widget _templateChip(String emoji, String name, int duration,
      Color surf, Color border, Color ts) {
    return GestureDetector(
      onTap: () => setState(() {
        _nameCtrl.text = name;
        _durCtrl.text  = '$duration';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:        surf,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: border),
        ),
        child: Text(emoji,
            style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hintText, required IconData prefixIcon,
    required Color surf, required Color border,
    required Color tp, required Color ts,
    bool obscureText = false, TextInputType? keyboardType,
    Widget? suffixIcon, String? Function(String?)? validator,
    VoidCallback? onEditingComplete,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onEditingComplete: onEditingComplete,
      style: TextStyle(color: tp, fontSize: 15),
      decoration: InputDecoration(
        hintText: hintText, hintStyle: TextStyle(color: ts, fontSize: 14),
        prefixIcon: Icon(prefixIcon, color: ts, size: 20),
        suffixIcon: suffixIcon,
        filled: true, fillColor: surf,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
        errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
      ),
    );
  }

  Widget _buildPrioritySelector(Color surf, Color border, Color ts) {
    const items = [
      (level: 1, label: 'Çok Düşük',  color: AppColors.prio1),
      (level: 2, label: 'Düşük',      color: AppColors.prio2),
      (level: 3, label: 'Orta',       color: AppColors.prio3),
      (level: 4, label: 'Yüksek',     color: AppColors.prio4),
      (level: 5, label: 'Çok Yüksek', color: AppColors.prio5),
    ];
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: items.map((item) {
        final selected = _priority == item.level;
        return GestureDetector(
          onTap: () => setState(() => _priority = item.level),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:        selected ? item.color.withOpacity(0.12) : surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? item.color : border,
                  width: selected ? 1.5 : 1),
            ),
            child: Text(item.label, style: TextStyle(
              color:      selected ? item.color : ts,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            )),
          ),
        );
      }).toList(),
    );
  }
}

// ── Yardımcı widget'lar ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text; final Color color;
  const _SectionLabel({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: color, letterSpacing: 0.2));
}

class _PickerTile extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap;
  final Color surf, border, tp, ts;
  const _PickerTile({required this.icon, required this.label,
    required this.onTap, required this.surf, required this.border,
    required this.tp, required this.ts});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border)),
      child: Row(children: [
        Icon(icon, color: ts, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: TextStyle(color: tp, fontSize: 14,
                fontWeight: FontWeight.w500))),
        Icon(Icons.chevron_right, color: ts, size: 18),
      ]),
    ),
  );
}