import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../core/models/task_model.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../suggest/map_picker_screen.dart';

class EditTaskScreen extends StatefulWidget {
  final TaskModel task;
  const EditTaskScreen({super.key, required this.task});

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen>
    with SingleTickerProviderStateMixin {
  final _formKey  = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _durCtrl;

  final GeocodingService _geocodingService = GeocodingService();
  late TextEditingController _noteCtrl;
  late TabController _tabCtrl;
  final MapController _mapCtrl = MapController();
  final _mapSearchCtrl = TextEditingController();
  bool _mapSearchLoading = false;
  LatLng? _markerPos;

  late int       _priority;
  late double    _latitude;
  late double    _longitude;
  bool           _geocodingLoading = false;
  late String    _coordinateText;
  late TimeOfDay _earliestStart;
  late DateTime  _selectedDate;

  // ── Tekrar alanları ───────────────────────────────────────
  late bool       _isRecurring;
  late String     _recurrenceType;
  late List<int>  _selectedDays;

  static const _dayNames = {
    1: 'Pzt', 2: 'Sal', 3: 'Çar',
    4: 'Per', 5: 'Cum', 6: 'Cmt', 7: 'Paz',
  };

  @override
  void initState() {
    super.initState();
    final task      = widget.task;
    _nameCtrl       = TextEditingController(text: task.name);
    _addressCtrl    = TextEditingController(text: task.address);
    _durCtrl        = TextEditingController(text: task.duration.toString());
    _priority       = task.priority;
    _latitude       = task.latitude;
    _longitude      = task.longitude;
    _coordinateText = 'Enlem: ${task.latitude.toStringAsFixed(5)}, '
        'Boylam: ${task.longitude.toStringAsFixed(5)}';
    _earliestStart  = TimeOfDay(
      hour:   (task.earliestStart ~/ 60) % 24,
      minute: task.earliestStart % 60,
    );
    final parts   = task.taskDate.split('-');
    _selectedDate = DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]),
    );

    // Tekrar
    _isRecurring    = task.isRecurring;
    _noteCtrl       = TextEditingController(text: task.note ?? '');
    _tabCtrl        = TabController(length: 2, vsync: this);
    _markerPos      = LatLng(_latitude, _longitude);
    _recurrenceType = task.recurrenceType ?? 'daily';
    _selectedDays   = task.recurrenceDays != null && task.recurrenceDays!.isNotEmpty
        ? task.recurrenceDays!.split(',')
        .map((d) => int.tryParse(d.trim()))
        .whereType<int>()
        .toList()
        : [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _durCtrl.dispose();
    _noteCtrl.dispose();
    _tabCtrl.dispose();
    _mapSearchCtrl.dispose();
    super.dispose();
  }

  String _formattedDate(String Function(String) t) {
    final now = DateTime.now();
    if (_selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day) return t('today');
    final tomorrow = now.add(const Duration(days: 1));
    if (_selectedDate.year == tomorrow.year &&
        _selectedDate.month == tomorrow.month &&
        _selectedDate.day == tomorrow.day) return t('tomorrow');
    return '${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}';
  }

  String get _taskDateString =>
      '${_selectedDate.year}-'
          '${_selectedDate.month.toString().padLeft(2, '0')}-'
          '${_selectedDate.day.toString().padLeft(2, '0')}';

  String get _timeString =>
      '${_earliestStart.hour.toString().padLeft(2, '0')}:'
          '${_earliestStart.minute.toString().padLeft(2, '0')}';

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _selectedDate.isBefore(DateTime.now())
          ? DateTime.now() : _selectedDate,
      firstDate: DateTime.now(),
      lastDate:  DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context:     context,
      initialTime: _earliestStart,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _earliestStart = picked);
  }

  Future<void> _geocodeAddress() async {
    final address = _addressCtrl.text.trim();
    if (address.isEmpty) return;
    setState(() {
      _geocodingLoading = true;
      _coordinateText   = 'Koordinatlar aranıyor...';
    });
    final result = await _geocodingService.addressToCoordinates(address);
    setState(() => _geocodingLoading = false);
    if (result != null) {
      setState(() {
        _latitude       = result['latitude']!;
        _longitude      = result['longitude']!;
        _coordinateText = 'Enlem: ${_latitude.toStringAsFixed(5)}, '
            'Boylam: ${_longitude.toStringAsFixed(5)}';
      });
    } else {
      setState(() => _coordinateText = 'Konum bulunamadı.');
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final duration = int.parse(_durCtrl.text.trim());
    final es       = _toMinutes(_earliestStart);

    final updated = TaskModel(
      id:             widget.task.id,
      name:           _nameCtrl.text.trim(),
      address:        _addressCtrl.text.trim(),
      latitude:       _latitude,
      longitude:      _longitude,
      duration:       duration,
      priority:       _priority,
      earliestStart:  es,
      latestFinish:   es + duration,
      taskDate:       _taskDateString,
      status:         widget.task.status,
      isRecurring:    _isRecurring,
      recurrenceType: _isRecurring ? _recurrenceType : null,
      recurrenceDays: _isRecurring && _recurrenceType == 'weekly'
          ? _selectedDays.join(',')
          : null,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    Navigator.pop(context, updated);
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
            child: Icon(Icons.close_rounded, color: tp, size: 18),
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
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text(t('edit_task'), style: TextStyle(color: tp, fontSize: 16,
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
              child: Text(t('save'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
            child: TabBar(
              controller:          _tabCtrl,
              labelColor:          const Color(0xFF6366F1),
              unselectedLabelColor: ts,
              indicatorColor:      const Color(0xFF6366F1),
              indicatorSize:       TabBarIndicatorSize.label,
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
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Görev Adı ──────────────────────────────
                  _SectionLabel(text: t('task_name'), color: ts),
                  const SizedBox(height: 8),
                  _buildField(
                    controller: _nameCtrl,
                    hintText:   'Toplantı, Ziyaret, Teslimat...',
                    prefixIcon: Icons.task_alt_outlined,
                    surf: surf, border: border, tp: tp, ts: ts,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                  ),
                  const SizedBox(height: 20),

                  // ── Adres ──────────────────────────────────
                  _SectionLabel(text: t('address'), color: ts),
                  const SizedBox(height: 8),
                  _buildField(
                    controller:        _addressCtrl,
                    hintText:          'Cadde, bina, ilçe...',
                    prefixIcon:        Icons.place_outlined,
                    onEditingComplete: _geocodeAddress,
                    surf: surf, border: border, tp: tp, ts: ts,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                    suffixIcon: _geocodingLoading
                        ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.orange),
                      ),
                    )
                        : IconButton(
                      icon: Icon(Icons.search_rounded,
                          color: AppColors.orange, size: 20),
                      onPressed: _geocodeAddress,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Haritadan konum seç
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push<MapPickerResult>(context,
                          MaterialPageRoute(builder: (_) => MapPickerScreen(
                            initialLat: _latitude != 0 ? _latitude : null,
                            initialLng: _longitude != 0 ? _longitude : null,
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
                          _latitude != 0 ? 'Konumu Değiştir (Haritadan)' : 'Haritadan Konum Seç',
                          style: const TextStyle(color: AppColors.orange,
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios, color: AppColors.orange, size: 12),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(
                      _coordinateText.startsWith('Enlem')
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size:  13,
                      color: _coordinateText.startsWith('Enlem')
                          ? AppColors.success : ts,
                    ),
                    const SizedBox(width: 5),
                    Expanded(child: Text(_coordinateText,
                        style: TextStyle(
                          fontSize: 12,
                          color: _coordinateText.startsWith('Enlem')
                              ? AppColors.success : ts,
                        ))),
                  ]),
                  const SizedBox(height: 20),

                  // ── Süre ───────────────────────────────────
                  _SectionLabel(text: t('duration'), color: ts),
                  const SizedBox(height: 8),
                  _buildField(
                    controller:   _durCtrl,
                    hintText:     '30',
                    prefixIcon:   Icons.timer_outlined,
                    keyboardType: TextInputType.number,
                    surf: surf, border: border, tp: tp, ts: ts,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Zorunlu alan';
                      final i = int.tryParse(v.trim());
                      if (i == null || i < 1) return 'En az 1 dakika';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── Öncelik ────────────────────────────────
                  _SectionLabel(text: t('priority'), color: ts),
                  const SizedBox(height: 10),
                  _buildPrioritySelector(surf, border, ts),
                  const SizedBox(height: 20),

                  // ── Tarih & Saat ───────────────────────────
                  Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(text: t('task_date'), color: ts),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(text: t('start_time'), color: ts),
                        const SizedBox(height: 8),
                        _PickerTile(
                          icon: Icons.access_time_outlined,
                          label: _timeString,
                          onTap: _pickTime,
                          surf: surf, border: border, tp: tp, ts: ts,
                        ),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 20),

                  // ── Tekrar ─────────────────────────────────
                  _SectionLabel(text: t('recurrence'), color: ts),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color:        surf,
                      borderRadius: BorderRadius.circular(12),
                      border:       Border.all(color: border),
                    ),
                    child: SwitchListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14),
                      title: Text(t('recurring_task'),
                          style: TextStyle(
                              color: tp, fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: _isRecurring
                          ? Text(
                        _buildRecurrenceSubtitle(),
                        style: TextStyle(
                            color: AppColors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      )
                          : null,
                      value:       _isRecurring,
                      activeColor: AppColors.orange,
                      onChanged:   (v) => setState(() => _isRecurring = v),
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
                      segments: [
                        ButtonSegment(value: 'daily',    label: Text(t('every_day'))),
                        ButtonSegment(value: 'weekdays', label: Text(t('weekdays'))),
                        ButtonSegment(value: 'weekly',   label: Text(t('weekly'))),
                      ],
                      selected:           {_recurrenceType},
                      onSelectionChanged: (s) =>
                          setState(() => _recurrenceType = s.first),
                    ),
                    if (_recurrenceType == 'weekly') ...[
                      const SizedBox(height: 12),
                      Text(t('which_days'),
                          style: TextStyle(fontSize: 13, color: ts)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: _dayNames.entries.map((e) {
                          final selected = _selectedDays.contains(e.key);
                          return GestureDetector(
                            onTap: () => setState(() {
                              selected
                                  ? _selectedDays.remove(e.key)
                                  : _selectedDays.add(e.key);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.orange.withOpacity(0.12) : surf,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected ? AppColors.orange : border,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(e.value,
                                  style: TextStyle(
                                    color: selected ? AppColors.orange : ts,
                                    fontWeight: selected
                                        ? FontWeight.w600 : FontWeight.w400,
                                    fontSize: 13,
                                  )),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Bilgi metni
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:        AppColors.info.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.info.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline,
                            size: 14, color: AppColors.info),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Görev tamamlandığında bir sonraki tekrar otomatik oluşturulur.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.info.withOpacity(0.9)),
                        )),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // ── Kaydet ─────────────────────────────────
                  // ── Not ─────────────────────────────────────────
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
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon:  const Icon(Icons.check_rounded, size: 18),
                      label: Text(t('save'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildMapTab(),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);
    final center = _markerPos ?? LatLng(_latitude, _longitude);
    return Column(children: [
      Container(
        color: surf,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _mapSearchCtrl,
              style: TextStyle(color: tp, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Konum ara...',
                hintStyle: TextStyle(color: ts, fontSize: 12),
                prefixIcon: Icon(Icons.search, color: ts, size: 18),
                filled: true, fillColor: AppColors.bg(context),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
              ),
              onSubmitted: (_) => _searchOnMap(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _mapSearchLoading ? null : _searchOnMap,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(10)),
              child: _mapSearchLoading
                  ? const Padding(padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
      Expanded(
        child: FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: center,
            initialZoom:   14,
            onTap: (_, latlng) => _setMarker(latlng),
            onLongPress: (_, latlng) => _setMarker(latlng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.mobile',
            ),
            if (_markerPos != null)
              MarkerLayer(markers: [
                Marker(
                  point: _markerPos!, width: 48, height: 56,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.orange, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.orange.withOpacity(0.4),
                            blurRadius: 8, spreadRadius: 2)],
                      ),
                      child: const Icon(Icons.place_rounded, color: Colors.white, size: 20),
                    ),
                    Container(width: 2, height: 10, color: AppColors.orange),
                  ]),
                ),
              ]),
          ],
        ),
      ),
    ]);
  }

  Future<void> _searchOnMap() async {
    final q = _mapSearchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _mapSearchLoading = true);
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=\${Uri.encodeComponent(q)}&format=json&limit=1');
      final resp = await http.get(url, headers: {'User-Agent': 'SmartRoutePlanner/1.0'});
      final list = jsonDecode(resp.body) as List;
      if (list.isNotEmpty) {
        final lat = double.parse(list[0]['lat']);
        final lon = double.parse(list[0]['lon']);
        setState(() {
          _markerPos = LatLng(lat, lon);
          _latitude  = lat;
          _longitude = lon;
          _coordinateText = list[0]['display_name'] as String;
        });
        _mapCtrl.move(LatLng(lat, lon), 15);
      }
    } catch (_) {}
    setState(() => _mapSearchLoading = false);
  }

  Future<void> _setMarker(LatLng pos) async {
    setState(() {
      _markerPos = pos;
      _latitude  = pos.latitude;
      _longitude = pos.longitude;
    });
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=\${pos.latitude}&lon=\${pos.longitude}&format=json');
      final resp = await http.get(url, headers: {'User-Agent': 'SmartRoutePlanner/1.0'});
      final data = jsonDecode(resp.body);
      if (data['display_name'] != null) {
        setState(() => _coordinateText = data['display_name'] as String);
      }
    } catch (_) {}
  }

  String _buildRecurrenceSubtitle() {
    switch (_recurrenceType) {
      case 'daily':    return 'Her gün tekrarlanır';
      case 'weekdays': return 'Hafta içi her gün tekrarlanır';
      case 'weekly':
        if (_selectedDays.isEmpty) return 'Haftalık — gün seçin';
        final names = _selectedDays
          ..sort();
        return 'Her ${names.map((d) => _dayNames[d] ?? '').join(', ')}';
      default:         return '';
    }
  }

  Widget _buildField({
    required TextEditingController     controller,
    required String                    hintText,
    required IconData                  prefixIcon,
    required Color                     surf,
    required Color                     border,
    required Color                     tp,
    required Color                     ts,
    bool                               obscureText  = false,
    TextInputType?                     keyboardType,
    Widget?                            suffixIcon,
    String? Function(String?)?         validator,
    VoidCallback?                      onEditingComplete,
  }) {
    return TextFormField(
      controller:        controller,
      obscureText:       obscureText,
      keyboardType:      keyboardType,
      validator:         validator,
      onEditingComplete: onEditingComplete,
      style: TextStyle(color: tp, fontSize: 15),
      decoration: InputDecoration(
        hintText:       hintText,
        hintStyle:      TextStyle(color: ts, fontSize: 14),
        prefixIcon:     Icon(prefixIcon, color: ts, size: 20),
        suffixIcon:     suffixIcon,
        filled:         true,
        fillColor:      surf,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
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
              color: selected ? item.color.withOpacity(0.12) : surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? item.color : border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(item.label,
                style: TextStyle(
                  color:      selected ? item.color : ts,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontSize:   13,
                )),
          ),
        );
      }).toList(),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color  color;
  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600,
        color: color, letterSpacing: 0.2,
      ));
}

class _PickerTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final Color        surf, border, tp, ts;

  const _PickerTile({
    required this.icon, required this.label, required this.onTap,
    required this.surf, required this.border,
    required this.tp,   required this.ts,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: border),
      ),
      child: Row(children: [
        Icon(icon, color: ts, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: TextStyle(
                color: tp, fontSize: 14, fontWeight: FontWeight.w500))),
        Icon(Icons.chevron_right, color: ts, size: 18),
      ]),
    ),
  );
}