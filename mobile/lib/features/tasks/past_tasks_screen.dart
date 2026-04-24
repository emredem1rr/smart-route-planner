import 'package:flutter/material.dart';
import '../../core/models/task_model.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';

class PastTasksScreen extends StatefulWidget {
  const PastTasksScreen({super.key});
  @override
  State<PastTasksScreen> createState() => _PastTasksScreenState();
}

class _PastTasksScreenState extends State<PastTasksScreen> {
  final _auth = AuthService();
  bool _loading = true;
  List<TaskModel> _pastTasks = [];
  final Set<int>  _selected  = {};
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now  = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final fromStr = '${from.year}-${from.month.toString().padLeft(2,'0')}-${from.day.toString().padLeft(2,'0')}';
      final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      final tasks = await _auth.getRemoteTasks(dateFrom: fromStr, dateTo: todayStr);
      // Bugün hariç geçmiş görevler — benzersiz isimler
      final seen = <String>{};
      final past = tasks.where((t) {
        if (t.taskDate == todayStr) return false;
        if (seen.contains(t.name))  return false;
        seen.add(t.name);
        return true;
      }).toList();
      setState(() => _pastTasks = past);
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    final now      = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    int saved = 0;
    for (final idx in _selected) {
      final t = _pastTasks[idx];
      final newTask = TaskModel(
        id:            0,
        name:          t.name,
        address:       t.address,
        latitude:      t.latitude,
        longitude:     t.longitude,
        duration:      t.duration,
        priority:      t.priority,
        earliestStart: t.earliestStart,
        latestFinish:  t.latestFinish,
        taskDate:      todayStr,
        note:          t.note,
      );
      final ok = await _auth.saveRemoteTask(newTask);
      if (ok) saved++;
    }
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text('$saved görev bugüne eklendi'),
      backgroundColor: AppColors.success,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    Navigator.pop(context, saved > 0);
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
            child: const Icon(Icons.history_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('Geçmiş Görevler', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _saving ? null : _addSelected,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Bugüne Ekle (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _pastTasks.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history_rounded, size: 56, color: ts),
        const SizedBox(height: 12),
        Text('Son 30 günde görev yok', style: TextStyle(color: ts, fontSize: 15)),
      ]))
          : Column(children: [
        // Tümünü seç
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            Text('${_pastTasks.length} görev bulundu',
                style: TextStyle(color: ts, fontSize: 13)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _pastTasks.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(List.generate(_pastTasks.length, (i) => i));
                }
              }),
              child: Text(
                _selected.length == _pastTasks.length ? 'Seçimi Kaldır' : 'Tümünü Seç',
                style: const TextStyle(color: AppColors.orange, fontSize: 13),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: _pastTasks.length,
            itemBuilder: (_, i) {
              final t      = _pastTasks[i];
              final sel    = _selected.contains(i);
              final colors = [AppColors.prio1, AppColors.prio2,
                AppColors.prio3, AppColors.prio4, AppColors.prio5];

              return GestureDetector(
                onTap: () => setState(() {
                  sel ? _selected.remove(i) : _selected.add(i);
                }),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.orange.withOpacity(0.06) : surf,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? AppColors.orange : border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color:        sel ? AppColors.orange : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border:       Border.all(
                          color: sel ? AppColors.orange : border,
                          width: 1.5,
                        ),
                      ),
                      child: sel
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color:  colors[t.priority - 1],
                        shape:  BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name, style: TextStyle(color: tp,
                              fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(
                            '${t.taskDate}  ·  ${t.duration} dk'
                                '${t.address.isNotEmpty ? "  ·  ${t.address}" : ""}',
                            style: TextStyle(color: ts, fontSize: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ])),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}