import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/task_model.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final AuthService         _authService  = AuthService();
  final NotificationService _notifService = NotificationService();

  DateTime             _currentMonth = DateTime.now();
  DateTime?            _selectedDay;
  List<TaskModel>      _dayTasks     = [];
  Map<String, dynamic> _dateInfo     = {};
  bool                 _loadingDates = false;
  bool                 _loadingTasks = false;

  static const _months = [
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _days = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];

  @override
  void initState() {
    super.initState();
    _loadMonthDates();
  }

  Future<void> _loadMonthDates() async {
    setState(() => _loadingDates = true);
    try {
      final dates = await _authService.getTaskDates(
        month: _currentMonth.month,
        year:  _currentMonth.year,
      );
      final map = <String, dynamic>{};
      for (final d in dates) {
        final dateKey = (d['task_date'] ?? '').toString();
        if (dateKey.isEmpty) continue;
        // MySQL SUM() int veya String döndürebilir — ikisini de handle et
        final pending = int.tryParse((d['pending_count'] ?? 0).toString()) ?? 0;
        final done    = int.tryParse((d['done_count']    ?? 0).toString()) ?? 0;
        map[dateKey] = {
          'pending_count': pending,
          'done_count':    done,
        };
      }
      debugPrint('[Calendar] loaded ${map.length} dates: $map');
      setState(() {
        _dateInfo     = map;
        _loadingDates = false;
      });
    } catch (e) {
      setState(() => _loadingDates = false);
    }
  }

  Future<void> _loadDayTasks(DateTime day) async {
    setState(() {
      _selectedDay  = day;
      _loadingTasks = true;
      _dayTasks     = [];
    });
    final tasks = await _authService.getRemoteTasks(date: _fmt(day));
    setState(() {
      _dayTasks     = tasks;
      _loadingTasks = false;
    });
  }

  Future<void> _deleteTask(TaskModel task) async {
    await _authService.deleteRemoteTask(task.id);
    await _notifService.cancelTaskNotification(task.id);
    setState(() => _dayTasks.removeWhere((t) => t.id == task.id));
    _loadMonthDates();
  }

  Future<void> _updateStatus(TaskModel task, String status) async {
    await _authService.updateTaskStatus(task.id, status);
    if (status == 'done' || status == 'cancelled') {
      await _notifService.cancelTaskNotification(task.id);
    }
    await _loadDayTasks(_selectedDay!);
    _loadMonthDates();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isPast(DateTime d) =>
      d.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

  bool _isFuture(DateTime d) =>
      d.isAfter(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _selectedDay  = null; _dayTasks = [];
    });
    _loadMonthDates();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _selectedDay  = null; _dayTasks = [];
    });
    _loadMonthDates();
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
        backgroundColor: surf, elevation: 0, surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
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
            child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('Takvim', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Column(children: [
        Container(
          color: surf,
          child: Column(children: [
            _buildMonthHeader(tp, ts),
            _buildDayHeaders(ts),
            const SizedBox(height: 4),
            _loadingDates
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(color: AppColors.orange),
            )
                : _buildGrid(surf, border, tp, ts),
            const SizedBox(height: 8),
            _buildLegend(ts),
            const SizedBox(height: 8),
            Divider(height: 1, color: border),
          ]),
        ),
        Expanded(
          child: _selectedDay == null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.touch_app_outlined, size: 36, color: AppColors.textDim(context)),
            const SizedBox(height: 10),
            Text('Bir gün seçin', style: TextStyle(color: ts, fontSize: 14)),
          ]))
              : _buildDayPanel(t, surf, border, tp, ts),
        ),
      ]),
    );
  }

  Widget _buildMonthHeader(Color tp, Color ts) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: tp), onPressed: _prevMonth),
          Text('${_months[_currentMonth.month]} ${_currentMonth.year}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tp)),
          IconButton(icon: Icon(Icons.chevron_right, color: tp), onPressed: _nextMonth),
        ],
      ),
    );
  }

  Widget _buildDayHeaders(Color ts) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: _days.map((d) => Expanded(
          child: Center(child: Text(d,
              style: TextStyle(fontWeight: FontWeight.w600, color: ts, fontSize: 12))),
        )).toList(),
      ),
    );
  }

  Widget _buildGrid(Color surf, Color border, Color tp, Color ts) {
    final firstDay    = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay     = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startOffset = firstDay.weekday - 1;

    final cells = <Widget>[
      for (int i = 0; i < startOffset; i++) const SizedBox(),
      for (int d = 1; d <= lastDay.day; d++)
        _buildCell(d, tp, ts),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      childAspectRatio: 1,
      children: cells,
    );
  }

  Widget _buildCell(int d, Color tp, Color ts) {
    final day     = DateTime(_currentMonth.year, _currentMonth.month, d);
    final dateStr = _fmt(day);
    final info    = _dateInfo[dateStr];
    final isToday = _isToday(day);
    final isPast  = _isPast(day);
    final isFut   = _isFuture(day);
    final isSel   = _selectedDay != null &&
        _selectedDay!.year  == day.year &&
        _selectedDay!.month == day.month &&
        _selectedDay!.day   == day.day;

    final pending = (info?['pending_count'] ?? 0) as int;
    final done    = (info?['done_count']    ?? 0) as int;
    final hasTask = pending + done > 0;

    // Sayı rengi
    Color numColor;
    if (isSel)          numColor = Colors.white;
    else if (isToday)   numColor = AppColors.orange;
    else if (hasTask && isPast) {
      numColor = (done > 0 && pending == 0) ? AppColors.success : AppColors.danger;
    }
    else if (hasTask && isFut) numColor = AppColors.info;
    else if (isPast)    numColor = AppColors.textDim(context);
    else                numColor = AppColors.textPrimary(context);

    // Arka plan
    Color? bgColor;
    if (isSel)          bgColor = AppColors.orange;
    else if (isToday)   bgColor = AppColors.orange.withOpacity(0.1);
    else if (hasTask && isPast) {
      bgColor = (done > 0 && pending == 0)
          ? AppColors.success.withOpacity(0.1)
          : AppColors.danger.withOpacity(0.08);
    }
    else if (hasTask && isFut) bgColor = AppColors.info.withOpacity(0.1);

    return GestureDetector(
      onTap: () => _loadDayTasks(day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color:        bgColor,
          borderRadius: BorderRadius.circular(8),
          border: isToday && !isSel
              ? Border.all(color: AppColors.orange, width: 1.5)
              : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$d',
              style: TextStyle(
                color:      numColor,
                fontWeight: hasTask || isToday || isSel ? FontWeight.w700 : FontWeight.w400,
                fontSize:   13,
              )),
          if (hasTask)
            Container(
              width: 5, height: 5,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: isSel ? Colors.white70 : numColor,
                shape: BoxShape.circle,
              ),
            )
          else
            const SizedBox(height: 7),
        ]),
      ),
    );
  }

  Widget _buildLegend(Color ts) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendDot(AppColors.success, 'Tamamlandı', ts),
          const SizedBox(width: 14),
          _legendDot(AppColors.danger, 'Bekleyen (Geçmiş)', ts),
          const SizedBox(width: 14),
          _legendDot(AppColors.info, 'Planlı (Gelecek)', ts),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label, Color ts) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10, color: ts)),
    ],
  );

  Widget _buildDayPanel(String Function(String) t,
      Color surf, Color border, Color tp, Color ts) {
    if (_loadingTasks) {
      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
    }

    final isPastDay = _isPast(_selectedDay!);
    final pending   = _dayTasks.where((t) => t.status == 'pending').toList();
    final others    = _dayTasks.where((t) => t.status != 'pending').toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(children: [
          Text('${_selectedDay!.day} ${_months[_selectedDay!.month]}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tp)),
          const SizedBox(width: 8),
          if (isPastDay)
            _chip('Geçmiş', AppColors.textDim(context))
          else if (_isFuture(_selectedDay!) && _dayTasks.isNotEmpty)
            _chip('Planlı', AppColors.info),
          const Spacer(),
          Text('${_dayTasks.length} görev', style: TextStyle(color: ts, fontSize: 13)),
        ]),
      ),
      Expanded(
        child: _dayTasks.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_available_outlined, size: 36, color: AppColors.textDim(context)),
          const SizedBox(height: 10),
          Text('Bu gün için görev yok', style: TextStyle(color: ts, fontSize: 14)),
        ]))
            : ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            // Geçmiş günde bekleyen görevler uyarısı
            if (isPastDay && pending.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color:        AppColors.danger.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.danger.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text('${pending.length} görev yapılmamış',
                      style: const TextStyle(fontSize: 12, color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            if (isPastDay && pending.isNotEmpty)
              ...pending.map((task) => _buildTaskCard(task, surf, border, tp, ts)),
            if (isPastDay && pending.isNotEmpty && others.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(child: Divider(color: border)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Diğer', style: TextStyle(color: ts, fontSize: 11))),
                  Expanded(child: Divider(color: border)),
                ]),
              ),
            ...( isPastDay ? others : _dayTasks)
                .map((task) => _buildTaskCard(task, surf, border, tp, ts)),
          ],
        ),
      ),
    ]);
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _buildTaskCard(TaskModel task, Color surf, Color border, Color tp, Color ts) {
    final Color statusColor;
    switch (task.status) {
      case 'done':      statusColor = AppColors.success; break;
      case 'cancelled': statusColor = AppColors.textDim(context); break;
      default:          statusColor = AppColors.info;
    }
    final prioColor = _prioColor(task.priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surf, borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: task.status == 'pending' && _isPast(_selectedDay!)
              ? AppColors.danger.withOpacity(0.25) : border,
        ),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: prioColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text('${task.priority}',
              style: TextStyle(color: prioColor, fontWeight: FontWeight.w700, fontSize: 13))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: tp)),
          if (task.address.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(task.address, style: TextStyle(color: ts, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.timer_outlined, size: 11, color: ts),
            const SizedBox(width: 3),
            Text('${task.duration} dk', style: TextStyle(color: ts, fontSize: 11)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_statusLabel(task.status),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ]),
        ])),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: ts, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) => v == 'delete' ? _deleteTask(task) : _updateStatus(task, v),
          itemBuilder: (_) => [
            _menuItem('pending',   Icons.radio_button_unchecked, AppColors.info,           'Bekliyor'),
            _menuItem('done',      Icons.check_circle_outline,   AppColors.success,        'Tamamlandı'),
            _menuItem('cancelled', Icons.cancel_outlined,        AppColors.textDim(context), 'İptal et'),
            const PopupMenuDivider(),
            _menuItem('delete',    Icons.delete_outline,         AppColors.danger,         'Sil'),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color color, String label) =>
      PopupMenuItem(value: value,
          child: Row(children: [
            Icon(icon, color: color, size: 18), const SizedBox(width: 10),
            Text(label, style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14)),
          ]));

  Color _prioColor(int p) {
    switch (p) {
      case 5: return AppColors.prio5;
      case 4: return AppColors.prio4;
      case 3: return AppColors.prio3;
      case 2: return AppColors.prio2;
      default: return AppColors.prio1;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'done':      return 'Tamamlandı';
      case 'cancelled': return 'İptal';
      default:          return 'Bekliyor';
    }
  }
}