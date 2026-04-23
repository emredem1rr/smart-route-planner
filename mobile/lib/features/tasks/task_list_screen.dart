import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../../core/models/task_model.dart';
import '../../core/models/optimize_request_model.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/local_optimizer.dart';
import '../../core/services/location_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/geofence_service.dart';
import '../../core/services/widget_service.dart';
import '../stats/stats_screen.dart';
import '../route/route_history_screen.dart';
import 'bulk_add_screen.dart';
import 'past_tasks_screen.dart';
import '../notifications/notification_center_screen.dart';
import '../../core/providers/settings_provider.dart';
import '../route/route_result_screen.dart';
import '../auth/login_screen.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart' hide EditTaskScreen;
import '../benchmark/benchmark_screen.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';
import '../suggest/suggest_screen.dart';

// ── Tema renkleri ──────────────────────────────────────────────
class _K {
  // Sabit
  static const indigo      = Color(0xFF6366F1);
  static const indigoDark  = Color(0xFF4F46E5);
  static const violet      = Color(0xFF8B5CF6);
  static const success     = Color(0xFF10B981);
  static const warn        = Color(0xFFF59E0B);
  static const danger      = Color(0xFFEF4444);
  static const dangerDark  = Color(0xFFDC2626);

  // Koyu tema
  static const dkBg        = Color(0xFF0F172A);
  static const dkSurf      = Color(0xFF1E293B);
  static const dkSurf2     = Color(0xFF334155);
  static const dkBorder    = Color(0xFF334155);
  static const dkText      = Color(0xFFFFFFFF);
  static const dkText2     = Color(0xFF94A3B8);
  static const dkText3     = Color(0xFF475569);
  static const dkIndigoSoft= Color(0xFF312E81);

  // Açık tema
  static const ltBg        = Color(0xFFF8FAFC);
  static const ltSurf      = Color(0xFFFFFFFF);
  static const ltSurf2     = Color(0xFFF1F5F9);
  static const ltBorder    = Color(0xFFCBD5E1);
  static const ltText      = Color(0xFF0F172A);
  static const ltText2     = Color(0xFF64748B);
  static const ltText3     = Color(0xFF94A3B8);
  static const ltIndigoSoft= Color(0xFFEEF2FF);

  static Color bg(bool d)          => d ? dkBg         : ltBg;
  static Color surf(bool d)        => d ? dkSurf        : ltSurf;
  static Color surf2(bool d)       => d ? dkSurf2       : ltSurf2;
  static Color border(bool d)      => d ? dkBorder      : ltBorder;
  static Color text(bool d)        => d ? dkText        : ltText;
  static Color text2(bool d)       => d ? dkText2       : ltText2;
  static Color text3(bool d)       => d ? dkText3       : ltText3;
  static Color indigoSoft(bool d)  => d ? dkIndigoSoft  : ltIndigoSoft;
  static Color dangerSoft(bool d)  => d ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
  static Color successSoft(bool d) => d ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
  static Color warnSoft(bool d)    => d ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
}

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});
  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with SingleTickerProviderStateMixin {

  final _tasks        = <TaskModel>[];
  final _overdueTasks = <TaskModel>[];
  bool  _overdueExpanded = true;

  final _api      = ApiService();
  final _auth     = AuthService();
  final _sync     = SyncService();
  final _loc      = LocationService();
  final _storage  = StorageService();
  final _localOpt = LocalOptimizer();
  final _geo      = GeofenceService();

  Position? _pos;
  bool   _locLoad   = false;
  bool   _opt       = false;
  bool   _loading   = true;
  bool   _online    = true;
  String _userName  = '';

  late final AnimationController _pulse;
  late final Animation<double>   _pulseAnim;
  Position? _lastPos;
  static const _reroute = 100.0;

  final _searchCtrl   = TextEditingController();
  String _searchQuery = '';
  String _sortMode    = 'time';
  bool   _searchOpen  = false;

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  String get _dateLabel {
    final n = DateTime.now();
    const d = ['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi','Pazar'];
    const m = ['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
    return '${d[n.weekday-1]}, ${n.day} ${m[n.month-1]}';
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _storage.getUserName().then((n) => setState(() => _userName = n ?? ''));
    _loadTasks();
    Connectivity().checkConnectivity().then((r) =>
        setState(() => _online = r != ConnectivityResult.none));
    Connectivity().onConnectivityChanged.listen((r) {
      final on = r != ConnectivityResult.none;
      setState(() => _online = on);
      if (on) { SyncService().syncPending(); _loadTasks(); }
    });
  }

  @override
  void dispose() { _pulse.dispose(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    List<TaskModel> todayList = [];
    try {
      todayList = await _sync.getTasks(date: _today);
    } catch (e) {
      debugPrint('getTasks error: \$e');
      setState(() => _loading = false);
      return;
    }
    final now  = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final yest = now.subtract(const Duration(days: 1));
    final fs   = '${from.year}-${from.month.toString().padLeft(2,'0')}-${from.day.toString().padLeft(2,'0')}';
    final ys   = '${yest.year}-${yest.month.toString().padLeft(2,'0')}-${yest.day.toString().padLeft(2,'0')}';
    List<TaskModel> overdue = [];
    try {
      overdue = await _sync.getOverdueTasks(dateFrom: fs, dateTo: ys);
    } catch (e) {
      debugPrint('getOverdueTasks error: $e');
    }
    setState(() {
      _tasks.clear(); _overdueTasks.clear();
      final p = todayList.where((t) => t.status == 'pending').toList()
        ..sort((a,b) => b.id.compareTo(a.id));
      _tasks.addAll(p);
      overdue.sort((a,b) => b.taskDate.compareTo(a.taskDate));
      _overdueTasks.addAll(overdue);
      _loading = false;
    });
    WidgetService.updateWidget(_tasks);
    _geo.start(_tasks);
  }

  List<TaskModel> get _filtered {
    var l = _tasks.where((t) => _searchQuery.isEmpty
        || t.name.toLowerCase().contains(_searchQuery.toLowerCase())
        || t.address.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    switch (_sortMode) {
      case 'priority': l.sort((a,b) => b.priority.compareTo(a.priority));
      case 'alpha':    l.sort((a,b) => a.name.compareTo(b.name));
      default:         l.sort((a,b) => a.earliestStart.compareTo(b.earliestStart));
    }
    return l;
  }

  List<TaskModel> get _filteredOverdue => _searchQuery.isEmpty
      ? _overdueTasks
      : _overdueTasks.where((t) =>
  t.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      t.address.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

  Future<void> _getLoc() async {
    setState(() => _locLoad = true);
    try {
      final l = await _loc.getCurrentLocation();
      setState(() => _pos = l);
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
      ).listen((p) {
        setState(() => _pos = p);
        if (_lastPos != null) {
          final d = Geolocator.distanceBetween(
              _lastPos!.latitude, _lastPos!.longitude, p.latitude, p.longitude);
          if (d >= _reroute && _tasks.isNotEmpty) _autoOpt(p);
        }
      });
    } catch (e) { _snack(e.toString(), _K.danger); }
    finally { setState(() => _locLoad = false); }
  }

  OptimizeRequest _req(Position p) => OptimizeRequest(
    startLocation: StartLocation(latitude: p.latitude, longitude: p.longitude),
    tasks: _tasks.where((t) => t.status == 'pending').toList(),
    config: OptimizationConfig(heuristic: 'euclidean', useRealRoads: _online),
  );

  Future<void> _autoOpt(Position p) async {
    _lastPos = p;
    if (_tasks.isEmpty) return;
    final r = _online ? await _api.optimize(_req(p)) : _localOpt.optimize(_req(p));
    if (!mounted || !r.success || r.result == null) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RouteResultScreen(response: r)));
  }

  Future<void> _optimize() async {
    if (_pos == null)   { _snack('Konum alınmadı', _K.danger); return; }
    if (_tasks.isEmpty) { _snack('Bugün görev yok', _K.danger); return; }
    setState(() => _opt = true);
    _lastPos = _pos;
    final r = _online ? await _api.optimize(_req(_pos!)) : _localOpt.optimize(_req(_pos!));
    setState(() => _opt = false);
    if (!mounted) return;
    if (r.success && r.result != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => RouteResultScreen(response: r)));
    } else { _snack(r.error ?? 'Hata', _K.danger); }
  }

  Future<void> _addTask() async {
    final t = await Navigator.push<TaskModel>(context, MaterialPageRoute(
        builder: (_) => AddTaskScreen(taskId: DateTime.now().millisecondsSinceEpoch % 2147483647)));
    if (t != null) {
      if (await _sync.saveTask(t)) {
        await NotificationService().scheduleTaskNotification(t);
        _loadTasks();
      } else { _snack('Görev kaydedilemedi', _K.danger); }
    }
  }

  Future<void> _editTask(TaskModel task) async {
    final u = await Navigator.push<TaskModel>(context,
        MaterialPageRoute(builder: (_) => EditTaskScreen(task: task)));
    if (u != null && await _auth.updateRemoteTask(u)) _loadTasks();
  }

  Future<void> _updateStatus(TaskModel task, String s) async {
    if (!await _sync.updateStatus(task.id, s)) return;
    if (s == 'pending') {
      final u = task.copyWith(status: 'pending');
      setState(() { if (!_tasks.any((t) => t.id == u.id)) _tasks.insert(0, u); });
    } else {
      setState(() {
        _tasks.removeWhere((t) => t.id == task.id);
        _overdueTasks.removeWhere((t) => t.id == task.id);
      });
      if (s == 'done') {
        NotificationService().showNow(
            id: task.id + 2000, title: '✅ Tamamlandı!', body: '"${task.name}" bitti 🎉');
        _showDoneOverlay(task.name);
      }
      if (_pos != null && _tasks.isNotEmpty) _autoOpt(_pos!);
    }
  }

  void _showDoneOverlay(String name) {
    final ov = Overlay.of(context);
    late OverlayEntry e;
    e = OverlayEntry(builder: (_) => Stack(children: [
      ..._confetti(),
      _DoneOverlay(taskName: name),
    ]));
    ov.insert(e);
    Future.delayed(const Duration(milliseconds: 2200), e.remove);
  }

  List<Widget> _confetti() {
    const cols = [_K.indigo, _K.success, Color(0xFF3B82F6), Color(0xFFEC4899), Color(0xFFF59E0B)];
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    return List.generate(20, (i) => _Confetti(
        left: (i * 47.3 + 10) % w, color: cols[i % cols.length],
        delay: Duration(milliseconds: i * 60), height: h));
  }

  Future<void> _deleteTask(TaskModel task) async {
    bool all = false;
    if (task.isRecurring) {
      final dark = context.read<SettingsProvider>().isDark;
      final ch = await showDialog<String>(context: context, builder: (_) => AlertDialog(
        backgroundColor: _K.surf(dark),
        title: Text('Görevi Sil', style: TextStyle(color: _K.text(dark), fontWeight: FontWeight.w700)),
        content: Text('"${task.name}" tekrarlayan görev.',
            style: TextStyle(color: _K.text2(dark))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context,'cancel'),
              child: Text('İptal', style: TextStyle(color: _K.text2(dark)))),
          TextButton(onPressed: () => Navigator.pop(context,'single'),
              child: const Text('Sadece Bugün', style: TextStyle(color: _K.indigo, fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => Navigator.pop(context,'all'),
              child: const Text('Tümünü Sil', style: TextStyle(color: _K.danger, fontWeight: FontWeight.w700))),
        ],
      ));
      if (ch == null || ch == 'cancel') return;
      all = ch == 'all';
    }
    await _sync.deleteTask(task.id, deleteAll: all);
    await NotificationService().cancelTaskNotification(task.id);
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
      _overdueTasks.removeWhere((t) => t.id == task.id);
    });
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _snack(String msg, Color color) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final dark = context.watch<SettingsProvider>().isDark;
    return Scaffold(
      backgroundColor: _K.bg(dark),
      body: Column(children: [
        _safeTop(dark),
        Expanded(child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _header(dark)),
          SliverToBoxAdapter(child: _statsBar(dark)),
          SliverToBoxAdapter(child: _locCard(dark)),
          SliverToBoxAdapter(child: _listHeader(dark)),
          _loading
              ? const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _K.indigo, strokeWidth: 2)))
              : _tasks.isEmpty && _overdueTasks.isEmpty
              ? SliverFillRemaining(child: _empty(dark))
              : _list(dark),
        ])),
        _optimizeBar(dark),
      ]),
      bottomNavigationBar: _navBar(dark),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        // Geçmişten ekle
        FloatingActionButton.small(
          heroTag: 'past',
          onPressed: () async {
            final ok = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => const PastTasksScreen()));
            if (ok == true) _loadTasks();
          },
          backgroundColor: _K.surf(dark),
          foregroundColor: _K.indigo,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.history_rounded, size: 18),
        ),
        const SizedBox(height: 10),
        // Görev ekle
        FloatingActionButton(
          heroTag: 'add',
          onPressed: _addTask,
          backgroundColor: _K.indigo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
        ),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ── Güvenli üst alan ────────────────────────────────────────────
  Widget _safeTop(bool dark) => Container(
    color: _K.bg(dark),
    height: MediaQuery.of(context).padding.top,
  );

  // ── Header ──────────────────────────────────────────────────────
  Widget _header(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(children: [
        // Logo
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_K.indigo, _K.violet],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Smart Route',
              style: TextStyle(color: _K.text(dark), fontSize: 16,
                  fontWeight: FontWeight.w700, letterSpacing: -0.4)),
          Text(_dateLabel,
              style: TextStyle(color: _K.text3(dark), fontSize: 10)),
        ])),
        // Çevrimdışı
        if (!_online)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _K.warnSoft(dark), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wifi_off_rounded, color: _K.warn, size: 11),
              const SizedBox(width: 4),
              const Text('Çevrimdışı',
                  style: TextStyle(color: _K.warn, fontSize: 9, fontWeight: FontWeight.w600)),
            ]),
          ),
        // Bildirim
        _hdrBtn(Icons.notifications_outlined, dark, () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen()))),
        const SizedBox(width: 6),
        // 3 nokta menü
        _moreMenu(dark),
      ]),
    );
  }

  Widget _hdrBtn(IconData icon, bool dark, VoidCallback fn) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: _K.surf(dark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.border(dark)),
      ),
      child: Icon(icon, color: _K.text2(dark), size: 17),
    ),
  );

  Widget _moreMenu(bool dark) => PopupMenuButton<String>(
    icon: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: _K.surf(dark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.border(dark)),
      ),
      child: Icon(Icons.more_vert_rounded, color: _K.text2(dark), size: 17),
    ),
    padding: EdgeInsets.zero,
    color: _K.surf(dark),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    onSelected: (v) {
      switch (v) {
        case 'history':
          Navigator.push(context, MaterialPageRoute(builder: (_) => const RouteHistoryScreen())); break;
        case 'benchmark':
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BenchmarkScreen())); break;
        case 'notif':
          Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())); break;
        case 'logout': _logout(); break;
      }
    },
    itemBuilder: (_) => [
      _mi('history',   Icons.history_rounded,      'Rota Geçmişi',  dark),
      _mi('benchmark', Icons.science_outlined,     'Benchmark',     dark),
      const PopupMenuDivider(),
      _mi('logout',    Icons.logout_rounded,       'Çıkış Yap',     dark, isDanger: true),
    ],
  );

  PopupMenuItem<String> _mi(String val, IconData icon, String label, bool dark, {bool isDanger = false}) =>
      PopupMenuItem(value: val,
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                color: isDanger ? _K.dangerSoft(dark) : _K.indigoSoft(dark),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: isDanger ? _K.danger : _K.indigo, size: 15),
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
              color: isDanger ? _K.danger : _K.text(dark),
              fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );

  // ── Stats Bar ────────────────────────────────────────────────────
  Widget _statsBar(bool dark) {
    final done = _tasks.where((t) => t.status == 'done').length;
    final pend = _tasks.where((t) => t.status == 'pending').length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _K.surf(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _K.border(dark)),
      ),
      child: Row(children: [
        _stat('$pend',              'Bugün',   _K.indigo,   dark),
        _statDiv(dark),
        _stat('$done',              'Tamamlandı', _K.success, dark),
        _statDiv(dark),
        _stat('${_overdueTasks.length}', 'Geçmiş', _K.warn,    dark),
      ]),
    );
  }

  Widget _stat(String val, String label, Color color, bool dark) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Text(val, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800,
            letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: _K.text3(dark), fontSize: 9,
            fontWeight: FontWeight.w500)),
      ]),
    ),
  );

  Widget _statDiv(bool dark) => Container(width: 1, height: 36, color: _K.border(dark));

  // ── Konum kartı ──────────────────────────────────────────────────
  Widget _locCard(bool dark) {
    final has = _pos != null;
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, ch) => Transform.scale(scale: has ? _pulseAnim.value : 1.0, child: ch),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _K.surf(dark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: has ? _K.indigo.withOpacity(0.5) : _K.border(dark),
              width: has ? 1.5 : 1),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: has ? _K.indigoSoft(dark) : _K.surf2(dark),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(has ? Icons.my_location_rounded : Icons.location_off_rounded,
                color: has ? _K.indigo : _K.text3(dark), size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Başlangıç Konumu',
                style: TextStyle(color: _K.text2(dark), fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              has ? '${_pos!.latitude.toStringAsFixed(4)}, ${_pos!.longitude.toStringAsFixed(4)}'
                  : 'Konum alınmadı',
              style: TextStyle(color: _K.text(dark), fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ])),
          _locLoad
              ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo))
              : GestureDetector(
            onTap: _getLoc,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _K.indigoSoft(dark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(has ? 'Güncelle' : 'Konum Al',
                  style: const TextStyle(color: _K.indigo, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Liste başlığı ────────────────────────────────────────────────
  Widget _listHeader(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 16,
              decoration: BoxDecoration(color: _K.indigo, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('${_filtered.length} / ${_tasks.length} görev',
              style: TextStyle(color: _K.text(dark), fontSize: 14, fontWeight: FontWeight.w700)),
          if (_tasks.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: _K.indigoSoft(dark), borderRadius: BorderRadius.circular(8)),
              child: Text('${_tasks.length}',
                  style: const TextStyle(color: _K.indigo, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
          const Spacer(),
          _iconBtn(dark, _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
              _searchOpen ? _K.indigo : null, () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) { _searchQuery = ''; _searchCtrl.clear(); }
              })),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: _iconBtn(dark, Icons.sort_rounded,
                _sortMode != 'time' ? _K.indigo : null, null),
            color: _K.surf(dark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) => setState(() => _sortMode = v),
            itemBuilder: (_) => [
              _sortMi('time',     Icons.access_time_rounded,  'Saate göre',    dark),
              _sortMi('priority', Icons.flag_rounded,          'Önceliğe göre', dark),
              _sortMi('alpha',    Icons.sort_by_alpha_rounded, 'A-Z',           dark),
            ],
          ),
          const SizedBox(width: 6),
          _iconBtn(dark, Icons.refresh_rounded, null, _loadTasks),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _searchOpen
              ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _searchCtrl, autofocus: true,
              style: TextStyle(color: _K.text(dark), fontSize: 13),
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Görev ara...',
                hintStyle: TextStyle(color: _K.text3(dark), fontSize: 12),
                prefixIcon: Icon(Icons.search_rounded, color: _K.text3(dark), size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(onPressed: () => setState(() { _searchQuery = ''; _searchCtrl.clear(); }),
                    icon: Icon(Icons.clear_rounded, color: _K.text3(dark), size: 16))
                    : null,
                filled: true, fillColor: _K.surf(dark),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _K.border(dark))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _K.border(dark))),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(color: _K.indigo, width: 1.5)),
              ),
            ),
          )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _iconBtn(bool dark, IconData icon, Color? active, VoidCallback? fn) {
    final isActive = active != null;
    final w = GestureDetector(
      onTap: fn,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: isActive ? _K.indigoSoft(dark) : _K.surf(dark),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: isActive ? _K.indigo : _K.border(dark)),
        ),
        child: Icon(icon, color: isActive ? _K.indigo : _K.text2(dark), size: 15),
      ),
    );
    return w;
  }

  PopupMenuItem<String> _sortMi(String val, IconData icon, String label, bool dark) {
    final sel = _sortMode == val;
    return PopupMenuItem(value: val, child: Row(children: [
      Icon(icon, color: sel ? _K.indigo : _K.text2(dark), size: 15),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(
          color: sel ? _K.indigo : _K.text(dark),
          fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
      if (sel) ...[const Spacer(), const Icon(Icons.check_rounded, color: _K.indigo, size: 14)],
    ]));
  }

  // ── Görev listesi ────────────────────────────────────────────────
  Widget _list(bool dark) {
    final f  = _filtered;
    final fo = _filteredOverdue;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) {
          if (i < f.length) return _card(f[i], dark);
          if (fo.isNotEmpty && i == f.length) return _overdueHdr(dark);
          if (!_overdueExpanded) return const SizedBox.shrink();
          return _card(fo[i - f.length - 1], dark, overdue: true);
        },
        childCount: f.length + (fo.isNotEmpty ? (_overdueExpanded ? fo.length + 1 : 1) : 0),
      )),
    );
  }

  Widget _empty(bool dark) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 60, height: 60,
      decoration: BoxDecoration(color: _K.indigoSoft(dark), borderRadius: BorderRadius.circular(18)),
      child: const Icon(Icons.playlist_add_rounded, color: _K.indigo, size: 30),
    ),
    const SizedBox(height: 14),
    Text('Bugün görev yok',
        style: TextStyle(color: _K.text(dark), fontSize: 15, fontWeight: FontWeight.w600)),
    const SizedBox(height: 4),
    Text('+ butonuna basarak görev ekle',
        style: TextStyle(color: _K.text3(dark), fontSize: 12)),
  ]));

  Widget _overdueHdr(bool dark) => GestureDetector(
    onTap: () => setState(() => _overdueExpanded = !_overdueExpanded),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(width: 3, height: 15,
            decoration: BoxDecoration(color: _K.danger, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        const Text('Geçmiş Yapılmamış',
            style: TextStyle(color: _K.danger, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
          child: Text('${_filteredOverdue.length}',
              style: const TextStyle(color: _K.dangerDark, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        Icon(_overdueExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: _K.danger, size: 18),
      ]),
    ),
  );

  Widget _card(TaskModel task, bool dark, {bool overdue = false}) {
    final pc   = _pColor(task.priority);
    final soft = pc.withOpacity(dark ? 0.18 : 0.10);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _K.surf(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _K.border(dark)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Sol renkli çizgi
            Container(width: 4, color: pc),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _editTask(task),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                    child: Row(children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text('${task.priority}',
                            style: TextStyle(color: pc, fontWeight: FontWeight.w800, fontSize: 15))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(task.name,
                              style: TextStyle(color: _K.text(dark), fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis, maxLines: 1)),
                          if (task.isRecurring)
                            Padding(padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.repeat_rounded, size: 11, color: _K.text3(dark))),
                          if (overdue && task.taskDate.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(5)),
                              child: Text(_shortDate(task.taskDate),
                                  style: const TextStyle(fontSize: 9, color: _K.dangerDark, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 5),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(5)),
                            child: Text(_pLabel(task.priority),
                                style: TextStyle(color: pc, fontSize: 9, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.schedule_rounded, size: 10, color: _K.text3(dark)),
                          const SizedBox(width: 3),
                          Text('${task.duration} dk',
                              style: TextStyle(fontSize: 10, color: _K.text2(dark))),
                          if (task.address.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.location_on_rounded, size: 10, color: _K.text3(dark)),
                            const SizedBox(width: 3),
                            Expanded(child: Text(task.address,
                                style: TextStyle(fontSize: 10, color: _K.text2(dark)),
                                overflow: TextOverflow.ellipsis, maxLines: 1)),
                          ],
                        ]),
                        if (task.note != null && task.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.sticky_note_2_outlined, size: 10, color: _K.text3(dark)),
                            const SizedBox(width: 3),
                            Expanded(child: Text(task.note!,
                                style: TextStyle(fontSize: 10, color: _K.text3(dark)),
                                overflow: TextOverflow.ellipsis, maxLines: 1)),
                          ]),
                        ],
                      ])),
                      const SizedBox(width: 6),
                      _statusBtn(task, dark),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statusBtn(TaskModel task, bool dark) => PopupMenuButton<String>(
    padding: EdgeInsets.zero,
    icon: Container(
      width: 30, height: 30,
      decoration: BoxDecoration(color: _K.surf2(dark), borderRadius: BorderRadius.circular(9)),
      child: Icon(
          task.status == 'done' ? Icons.check_circle_rounded
              : task.status == 'cancelled' ? Icons.cancel_rounded
              : Icons.more_vert_rounded,
          color: task.status == 'done' ? _K.success
              : task.status == 'cancelled' ? _K.danger
              : _K.text2(dark),
          size: 15),
    ),
    color: _K.surf(dark),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: (v) => v == 'delete' ? _deleteTask(task) : _updateStatus(task, v),
    itemBuilder: (_) => [
      _stMi('pending',   Icons.radio_button_unchecked_rounded, _K.text2(dark), 'Bekliyor', dark),
      _stMi('done',      Icons.check_circle_rounded,           _K.success,     'Tamamlandı', dark),
      _stMi('cancelled', Icons.cancel_rounded,                 _K.danger,      'İptal', dark),
      const PopupMenuDivider(),
      _stMi('delete',    Icons.delete_outline_rounded,         _K.danger,      'Sil', dark, red: true),
    ],
  );

  PopupMenuItem<String> _stMi(String v, IconData i, Color c, String l, bool dark, {bool red = false}) =>
      PopupMenuItem(value: v, child: Row(children: [
        Icon(i, color: c, size: 16),
        const SizedBox(width: 10),
        Text(l, style: TextStyle(color: red ? _K.danger : _K.text(dark), fontSize: 13)),
      ]));

  // ── Optimize bar ──────────────────────────────────────────────────
  Widget _optimizeBar(bool dark) {
    final ready = !_opt && _tasks.isNotEmpty && _pos != null;
    return Container(
      color: _K.bg(dark),
      padding: const EdgeInsets.fromLTRB(16, 8, 90, 12),
      child: GestureDetector(
        onTap: _opt ? null : _optimize,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: ready ? const LinearGradient(
                colors: [_K.indigo, _K.violet],
                begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            color: ready ? null : _K.surf2(dark),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_opt)
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              Icon(_online ? Icons.route_rounded : Icons.wifi_off_rounded,
                  color: ready ? Colors.white : _K.text3(dark), size: 18),
            const SizedBox(width: 8),
            Text(
              _opt ? 'Optimize ediliyor...' : 'Rotayı Optimize Et  (${_tasks.length})',
              style: TextStyle(
                  color: ready ? Colors.white : _K.text3(dark),
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────
  Widget _navBar(bool dark) => Container(
    height: 60 + MediaQuery.of(context).padding.bottom,
    decoration: BoxDecoration(
      color: _K.surf(dark),
      border: Border(top: BorderSide(color: _K.border(dark))),
    ),
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
    child: Row(children: [
      _navItem(Icons.calendar_month_rounded, 'Takvim', dark, () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()))),
      _navItem(Icons.explore_rounded, 'Keşfet', dark, () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SuggestScreen()))),
      _navItem(Icons.playlist_add_rounded, 'Toplu', dark, () async {
        final ok = await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => const BulkAddScreen()));
        if (ok == true) _loadTasks();
      }),
      _navItem(Icons.bar_chart_rounded, 'İstatistik', dark, () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()))),
      _navItem(Icons.person_rounded, 'Profil', dark, () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
    ]),
  );

  Widget _navItem(IconData icon, String label, bool dark, VoidCallback onTap) =>
      Expanded(child: InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: _K.text2(dark), size: 21),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: _K.text2(dark), fontSize: 9, fontWeight: FontWeight.w500)),
        ]),
      ));

  // ── Yardımcılar ───────────────────────────────────────────────────
  String _shortDate(String s) {
    final p = s.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}' : s;
  }

  Color _pColor(int p) {
    switch (p) {
      case 5: return _K.danger;
      case 4: return const Color(0xFFF97316);
      case 3: return _K.indigo;
      case 2: return _K.success;
      default: return const Color(0xFF94A3B8);
    }
  }

  String _pLabel(int p) {
    switch (p) {
      case 5: return 'Çok Yüksek';
      case 4: return 'Yüksek';
      case 3: return 'Orta';
      case 2: return 'Düşük';
      default: return 'Çok Düşük';
    }
  }
}

// ── Konfeti ────────────────────────────────────────────────────────
class _Confetti extends StatefulWidget {
  final double left, height;
  final Color color;
  final Duration delay;
  const _Confetti({required this.left, required this.color, required this.delay, required this.height});
  @override State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fall, _rot;
  @override
  void initState() {
    super.initState();
    _c    = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _fall = Tween<double>(begin: -20, end: widget.height + 20)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
    _rot  = Tween<double>(begin: 0, end: 6.28).animate(_c);
    Future.delayed(widget.delay, () { if (mounted) _c.forward(); });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Positioned(
      left: widget.left, top: _fall.value,
      child: Transform.rotate(angle: _rot.value,
          child: Container(width: 8, height: 8,
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)))),
    ),
  );
}

// ── Tamamlama overlay ──────────────────────────────────────────────
class _DoneOverlay extends StatefulWidget {
  final String taskName;
  const _DoneOverlay({required this.taskName});
  @override State<_DoneOverlay> createState() => _DoneOverlayState();
}

class _DoneOverlayState extends State<_DoneOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _fade, _scale;
  @override
  void initState() {
    super.initState();
    _c     = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade  = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.7, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut));
    _c.forward();
    Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) _c.reverse(); });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Positioned(
    bottom: 120, left: 0, right: 0,
    child: Center(child: FadeTransition(opacity: _fade,
      child: ScaleTransition(scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
              color: _K.success, borderRadius: BorderRadius.circular(30)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text('${widget.taskName} tamamlandı!',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
      ),
    )),
  );
}