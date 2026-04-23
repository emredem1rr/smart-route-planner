import 'package:flutter/material.dart';
import '../../core/models/task_model.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';

class BulkAddScreen extends StatefulWidget {
  const BulkAddScreen({super.key});
  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _auth    = AuthService();
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  final List<_BulkTask> _items = [];
  bool _saving = false;

  // Hızlı ekle state
  int    _priority = 3;
  int    _duration = 30;
  TimeOfDay _time  = TimeOfDay.now();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    final name = _nameCtrl.text.trim();
    final addr = _addrCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _items.add(_BulkTask(
        name:     name,
        address:  addr,
        priority: _priority,
        duration: _duration,
        time:     _time,
      ));
      _nameCtrl.clear();
      _addrCtrl.clear();
    });
  }

  Future<void> _saveAll() async {
    if (_items.isEmpty) return;
    setState(() => _saving = true);
    final now    = DateTime.now();
    final today  = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    int saved = 0;
    for (final item in _items) {
      final es = item.time.hour * 60 + item.time.minute;
      final task = TaskModel(
        id:            0,
        name:          item.name,
        address:       item.address,
        latitude:      0,
        longitude:     0,
        duration:      item.duration,
        priority:      item.priority,
        earliestStart: es,
        latestFinish:  es + item.duration,
        taskDate:      today,
      );
      final ok = await _auth.saveRemoteTask(task);
      if (ok) saved++;
    }
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text('$saved görev eklendi'),
      backgroundColor: AppColors.success,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    Navigator.pop(context, saved > 0);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context:     context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (t != null) setState(() => _time = t);
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
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('Toplu Görev Ekle', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _saving ? null : _saveAll,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Kaydet (${_items.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Column(children: [
        // ── Hızlı ekleme formu ───────────────────────────────
        Container(
          color:   surf,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // Ad
            TextField(
              controller: _nameCtrl,
              style:      TextStyle(color: tp, fontSize: 14),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText:       'Görev adı...',
                hintStyle:      TextStyle(color: ts, fontSize: 13),
                prefixIcon:     Icon(Icons.task_alt_outlined, color: ts, size: 18),
                filled:         true, fillColor: bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
              ),
            ),
            const SizedBox(height: 8),
            // Adres
            TextField(
              controller: _addrCtrl,
              style:      TextStyle(color: tp, fontSize: 14),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addItem(),
              decoration: InputDecoration(
                hintText:       'Adres (opsiyonel)...',
                hintStyle:      TextStyle(color: ts, fontSize: 13),
                prefixIcon:     Icon(Icons.place_outlined, color: ts, size: 18),
                filled:         true, fillColor: bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
              ),
            ),
            const SizedBox(height: 10),
            // Süre + Saat + Öncelik
            Row(children: [
              // Süre
              _chip('${_duration}dk', Icons.timer_outlined, ts, () async {
                final opts = [15, 30, 45, 60, 90, 120];
                final idx  = await showDialog<int>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    backgroundColor: surf,
                    title: Text('Süre', style: TextStyle(color: tp)),
                    children: opts.map((m) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, m),
                      child: Text('$m dk', style: TextStyle(color: tp)),
                    )).toList(),
                  ),
                );
                if (idx != null) setState(() => _duration = idx);
              }),
              const SizedBox(width: 8),
              // Saat
              _chip(
                '${_time.hour.toString().padLeft(2,'0')}:${_time.minute.toString().padLeft(2,'0')}',
                Icons.access_time, ts, _pickTime,
              ),
              const SizedBox(width: 8),
              // Öncelik
              _chip('Öncelik $_priority', Icons.flag_outlined, ts, () async {
                final p = await showDialog<int>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    backgroundColor: surf,
                    title: Text('Öncelik', style: TextStyle(color: tp)),
                    children: [1,2,3,4,5].map((v) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, v),
                      child: Text(['Çok Düşük','Düşük','Orta','Yüksek','Çok Yüksek'][v-1],
                          style: TextStyle(color: tp)),
                    )).toList(),
                  ),
                );
                if (p != null) setState(() => _priority = p);
              }),
              const Spacer(),
              // Ekle butonu
              GestureDetector(
                onTap: _addItem,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color:        AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text('Ekle', style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
        Divider(height: 1, color: border),

        // ── Görev listesi ────────────────────────────────────
        Expanded(
          child: _items.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.playlist_add_rounded, size: 52, color: ts),
            const SizedBox(height: 12),
            Text('Henüz görev eklenmedi',
                style: TextStyle(color: ts, fontSize: 14)),
            const SizedBox(height: 6),
            Text('Yukarıdan hızlıca ekleyebilirsin',
                style: TextStyle(color: ts, fontSize: 12)),
          ]))
              : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final item   = _items[i];
              final colors = [AppColors.prio1, AppColors.prio2,
                AppColors.prio3, AppColors.prio4, AppColors.prio5];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: surf, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color:  colors[item.priority - 1],
                      shape:  BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: TextStyle(color: tp,
                            fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                          '${item.time.hour.toString().padLeft(2,'0')}:${item.time.minute.toString().padLeft(2,'0')}  ·  ${item.duration} dk'
                              '${item.address.isNotEmpty ? "  ·  ${item.address}" : ""}',
                          style: TextStyle(color: ts, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ])),
                  IconButton(
                    icon:      Icon(Icons.close, color: ts, size: 18),
                    onPressed: () => setState(() => _items.removeAt(i)),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, IconData icon, Color ts, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        AppColors.orangeDim,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: AppColors.orange),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.orange,
              fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _BulkTask {
  final String    name, address;
  final int       priority, duration;
  final TimeOfDay time;
  _BulkTask({
    required this.name, required this.address,
    required this.priority, required this.duration,
    required this.time,
  });
}