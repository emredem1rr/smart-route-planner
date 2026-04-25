import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../models/task_model.dart';
// navigatorKey, main.dart'ta tanımlandı
import '../../main.dart' show navigatorKey;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
    InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        // Rota bildirimlerine tıklanınca ana ekrana yönlendir
        final payload = details.payload ?? '';
        if (payload == 'route') {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      },
    );

    // Android 13+ için bildirim izni iste
    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Göreve ait bildirimi zamanla
  /// - 30 dakika önce: "Yaklaşan görev" uyarısı
  /// - Görev saatinde: "Başlama zamanı" bildirimi
  Future<void> scheduleTaskNotification(TaskModel task) async {
    await initialize();

    // task.taskDate: "2026-03-28"
    final parts = task.taskDate.split('-');
    if (parts.length != 3) return;

    final taskDate = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );

    // earliestStart dakika cinsinden (örn: 14*60+30 = 870 = 14:30)
    // earliestStart = 0 ise saat belirsiz — bildirim gönderme
    if (task.earliestStart <= 0) return;

    final taskStart = DateTime(
      taskDate.year,
      taskDate.month,
      taskDate.day,
      task.earliestStart ~/ 60,
      task.earliestStart % 60,
    );

    final now = DateTime.now();
    if (taskStart.isBefore(now)) return;

    // 1) 30 dakika önce bildirim
    final notifyBefore = taskStart.subtract(const Duration(minutes: 30));
    if (notifyBefore.isAfter(now)) {
      await _plugin.zonedSchedule(
        task.id * 10,     // ID çakışmasın diye *10
        '⏰ ${task.name}',
        '${_timeStr(task.earliestStart)} — 30 dakika kaldı'
            '${task.address.isNotEmpty ? '\n📍 ${task.address}' : ''}',
        tz.TZDateTime.from(notifyBefore, tz.local),
        _notifDetails('task_reminders', 'Görev Hatırlatıcıları'),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    // History'e kaydet — bildirim merkezinde görünsün
    _saveToHistory(
      title: '⏰ ${task.name}',
      body:  '${_timeStr(task.earliestStart)} — hatırlatıcı kuruldu',
      type:  'reminder',
    );

    // 2) Görev başlangıç saatinde bildirim
    await _plugin.zonedSchedule(
      task.id * 10 + 1,
      '🚀 ${task.name} başlıyor!',
      'Şimdi yola çıkma zamanı'
          '${task.address.isNotEmpty ? '\n📍 ${task.address}' : ''}',
      tz.TZDateTime.from(taskStart, tz.local),
      _notifDetails('task_start', 'Görev Başlangıçları'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Birden fazla görevi toplu zamanla
  Future<void> scheduleAllTasks(List<TaskModel> tasks) async {
    await initialize();
    for (final task in tasks) {
      await scheduleTaskNotification(task);
    }
  }

  /// Rota optimize edildikten sonra tüm görevler için bildirim kur
  Future<void> scheduleOptimizedRoute(List<dynamic> orderedTasks) async {
    await initialize();
    for (final task in orderedTasks) {
      if (task is TaskModel) {
        await scheduleTaskNotification(task);
      }
    }
  }

  /// Anında bildirim gönder (test veya acil durum)
  Future<void> showNow({
    required String title,
    required String body,
    int     id      = 0,
    String  type    = 'general',
    String? payload,
  }) async {
    await initialize();
    await _plugin.show(
      id, title, body,
      _notifDetails('instant', 'Anlık Bildirimler'),
      payload: payload,
    );
    _saveToHistory(title: title, body: body, type: type);
  }

  Future<void> _saveToHistory({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getStringList('notif_history') ?? [];
      raw.add(jsonEncode({
        'title': title,
        'body':  body,
        'type':  type,
        'time':  DateTime.now().toIso8601String(),
      }));
      if (raw.length > 50) raw.removeRange(0, raw.length - 50);
      await prefs.setStringList('notif_history', raw);
    } catch (_) {}
  }

  Future<void> cancelTaskNotification(int taskId) async {
    await initialize();
    await _plugin.cancel(taskId * 10);
    await _plugin.cancel(taskId * 10 + 1);
    _saveToHistory(
      title: 'Bildirim İptal',
      body:  'Görev bildirimi kaldırıldı',
      type:  'cancelled',
    );
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }

  // ── Yardımcılar ───────────────────────────────────────────
  String _timeStr(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  NotificationDetails _notifDetails(String channelId, String channelName) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance:       Importance.high,
        priority:         Priority.high,
        icon:             '@mipmap/ic_launcher',
        styleInformation: const BigTextStyleInformation(''),
      ),
    );
  }
}