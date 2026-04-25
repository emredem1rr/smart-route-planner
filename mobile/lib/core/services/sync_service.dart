import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'auth_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';
import '../models/task_model.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final LocalDbService _localDb     = LocalDbService();
  final AuthService    _authService = AuthService();

  // ── Connectivity ───────────────────────────────────────────
  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  // ── Get tasks ──────────────────────────────────────────────
  Future<List<TaskModel>> getTasks({String? date}) async {
    if (await isOnline()) {
      try {
        final tasks = await _authService.getRemoteTasks(date: date);
        await _localDb.saveAllTasks(tasks);
        return tasks;
      } catch (_) {
        return date != null ? await _localDb.getTasksByDate(date) : [];
      }
    } else {
      return date != null ? await _localDb.getTasksByDate(date) : [];
    }
  }

  // ── Geçmiş yapılmamış görevler — tek istekle ──────────────
  Future<List<TaskModel>> getOverdueTasks({
    required String dateFrom,
    required String dateTo,
  }) async {
    if (await isOnline()) {
      try {
        return await _authService.getRemoteTasks(
          dateFrom: dateFrom,
          dateTo:   dateTo,
          status:   'pending',
        );
      } catch (_) {
        return await _localDb.getOverdueTasks(dateFrom: dateFrom, dateTo: dateTo);
      }
    } else {
      return await _localDb.getOverdueTasks(dateFrom: dateFrom, dateTo: dateTo);
    }
  }

  // ── Save task ──────────────────────────────────────────────
  Future<bool> saveTask(TaskModel task) async {
    if (await isOnline()) {
      final ok = await _authService.saveRemoteTask(task);
      if (ok) await _localDb.saveTask(task, synced: true);
      return ok;
    } else {
      await _localDb.saveTask(task, synced: false);
      await _localDb.queueAction('save', task.id, jsonEncode(task.toJson()));
      return true;
    }
  }

  // ── Update status — tekrar mantığı burada ─────────────────
  Future<bool> updateStatus(int taskId, String status) async {
    await _localDb.updateStatus(taskId, status);

    // Görev tamamlandıysa tekrar kontrolü yap
    if (status == 'done') {
      await _handleRecurrence(taskId);
    }

    if (await isOnline()) {
      return await _authService.updateTaskStatus(taskId, status);
    } else {
      await _localDb.queueAction(
        'status', taskId, jsonEncode({'status': status}),
      );
      return true;
    }
  }

  // ── Delete task ────────────────────────────────────────────
  Future<bool> deleteTask(int taskId, {bool deleteAll = false}) async {
    await _localDb.deleteTask(taskId);

    if (await isOnline()) {
      return await _authService.deleteRemoteTask(taskId, deleteAll: deleteAll);
    } else {
      await _localDb.queueAction('delete', taskId, '');
      return true;
    }
  }

  // ── Tekrar: sonraki görevi oluştur ─────────────────────────
  Future<void> _handleRecurrence(int taskId) async {
    try {
      // Tamamlanan görevi bul
      final task = await _localDb.getTaskById(taskId);
      if (task == null || !task.isRecurring) return;

      final nextDate = _nextDate(task);
      if (nextDate == null) return;

      final nextTask = TaskModel(
        id:             DateTime.now().millisecondsSinceEpoch % 2147483647,
        name:           task.name,
        address:        task.address,
        latitude:       task.latitude,
        longitude:      task.longitude,
        duration:       task.duration,
        priority:       task.priority,
        earliestStart:  task.earliestStart,
        latestFinish:   task.latestFinish,
        taskDate:       _formatDate(nextDate),
        status:         'pending',
        isRecurring:    true,
        recurrenceType: task.recurrenceType,
        recurrenceDays: task.recurrenceDays,
      );

      await saveTask(nextTask);
      await NotificationService().scheduleTaskNotification(nextTask);
    } catch (e) {
      // Tekrar oluşturma başarısız olsa bile ana işlem etkilenmesin
      print('[SyncService] Recurrence error: $e');
    }
  }

  // ── Sonraki tarihi hesapla ─────────────────────────────────
  DateTime? _nextDate(TaskModel task) {
    if (task.taskDate.isEmpty) return null;

    final parts   = task.taskDate.split('-');
    final current = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );

    switch (task.recurrenceType) {
      case 'daily':
        return current.add(const Duration(days: 1));

      case 'weekdays':
      // Hafta içi: Cumartesi → Pazartesi, Cuma → Pazartesi
        var next = current.add(const Duration(days: 1));
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = next.add(const Duration(days: 1));
        }
        return next;

      case 'weekly':
        if (task.recurrenceDays == null || task.recurrenceDays!.isEmpty) {
          return current.add(const Duration(days: 7));
        }
        // Seçilen günlerin listesi: "1,3,5" gibi
        final days = task.recurrenceDays!
            .split(',')
            .map((d) => int.tryParse(d.trim()))
            .whereType<int>()
            .toList()
          ..sort();

        if (days.isEmpty) return current.add(const Duration(days: 7));

        // Mevcut günden sonra gelen ilk seçili günü bul
        final currentWeekday = current.weekday; // 1=Pzt, 7=Paz
        final nextDay = days.firstWhere(
              (d) => d > currentWeekday,
          orElse: () => -1,
        );

        if (nextDay != -1) {
          // Bu hafta içinde ilerki gün var
          return current.add(Duration(days: nextDay - currentWeekday));
        } else {
          // Gelecek haftanın ilk seçili gününe atla
          final daysUntilNextWeek = 7 - currentWeekday + days.first;
          return current.add(Duration(days: daysUntilNextWeek));
        }

      default:
        return null;
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';

  // ── Sync pending ───────────────────────────────────────────
  Future<void> syncPending() async {
    if (!await isOnline()) return;

    final actions = await _localDb.getPendingActions();
    for (final action in actions) {
      try {
        final type    = action['action'] as String;
        final taskId  = action['task_id'] as int;
        final payload = action['payload'] as String;

        if (type == 'save') {
          final task = TaskModel.fromJson(jsonDecode(payload));
          await _authService.saveRemoteTask(task);
          await _localDb.markSynced(taskId);
        } else if (type == 'status') {
          final data = jsonDecode(payload);
          await _authService.updateTaskStatus(taskId, data['status']);
        } else if (type == 'delete') {
          await _authService.deleteRemoteTask(taskId);
        }

        await _localDb.clearAction(action['id'] as int);
      } catch (_) {
        // Başarısız action'ı atla, bir sonraki senkronizasyonda tekrar dene
      }
    }
  }
}