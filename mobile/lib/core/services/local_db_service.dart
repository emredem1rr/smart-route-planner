import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task_model.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }
  // local_db_service.dart'a ekle

  Future<List<TaskModel>> getOverdueTasks({
    required String dateFrom,
    required String dateTo,
  }) async {
    final database = await db;
    final rows     = await database.query(
      'tasks',
      where:     'task_date >= ? AND task_date <= ? AND status = ?',
      whereArgs: [dateFrom, dateTo, 'pending'],
      orderBy:   'task_date DESC',
    );
    return rows.map(_rowToTask).toList();
  }
  Future<TaskModel?> getTaskById(int id) async {
    final db = await this.db;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TaskModel.fromJson(rows.first);
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'smart_route.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id              INTEGER PRIMARY KEY,
            name            TEXT    NOT NULL,
            address         TEXT    DEFAULT '',
            latitude        REAL    NOT NULL,
            longitude       REAL    NOT NULL,
            duration        INTEGER NOT NULL,
            priority        INTEGER NOT NULL DEFAULT 3,
            earliest_start  INTEGER NOT NULL DEFAULT 0,
            latest_finish   INTEGER NOT NULL DEFAULT 480,
            task_date       TEXT    NOT NULL,
            status          TEXT    NOT NULL DEFAULT 'pending',
            is_recurring    INTEGER NOT NULL DEFAULT 0,
            recurrence_type TEXT,
            recurrence_days TEXT,
            synced          INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_actions (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            action    TEXT NOT NULL,
            task_id   INTEGER,
            payload   TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
  }

  // ── Save task locally ──────────────────────────────────────
  Future<void> saveTask(TaskModel task, {bool synced = false}) async {
    final database = await db;
    await database.insert(
      'tasks',
      {
        'id':              task.id,
        'name':            task.name,
        'address':         task.address,
        'latitude':        task.latitude,
        'longitude':       task.longitude,
        'duration':        task.duration,
        'priority':        task.priority,
        'earliest_start':  task.earliestStart,
        'latest_finish':   task.latestFinish,
        'task_date':       task.taskDate,
        'status':          task.status,
        'is_recurring':    task.isRecurring ? 1 : 0,
        'recurrence_type': task.recurrenceType,
        'recurrence_days': task.recurrenceDays,
        'synced':          synced ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Save all tasks ─────────────────────────────────────────
  Future<void> saveAllTasks(List<TaskModel> tasks) async {
    final database = await db;
    final batch    = database.batch();
    for (final task in tasks) {
      batch.insert(
        'tasks',
        {
          'id':              task.id,
          'name':            task.name,
          'address':         task.address,
          'latitude':        task.latitude,
          'longitude':       task.longitude,
          'duration':        task.duration,
          'priority':        task.priority,
          'earliest_start':  task.earliestStart,
          'latest_finish':   task.latestFinish,
          'task_date':       task.taskDate,
          'status':          task.status,
          'is_recurring':    task.isRecurring ? 1 : 0,
          'recurrence_type': task.recurrenceType,
          'recurrence_days': task.recurrenceDays,
          'synced':          1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ── Get tasks by date ──────────────────────────────────────
  Future<List<TaskModel>> getTasksByDate(String date) async {
    final database = await db;
    final rows     = await database.query(
      'tasks',
      where:    'task_date = ? AND status = ?',
      whereArgs: [date, 'pending'],
      orderBy:  'earliest_start ASC',
    );
    return rows.map(_rowToTask).toList();
  }

  // ── Update task status locally ─────────────────────────────
  Future<void> updateStatus(int taskId, String status) async {
    final database = await db;
    await database.update(
      'tasks',
      {'status': status, 'synced': 0},
      where:     'id = ?',
      whereArgs: [taskId],
    );
  }

  // ── Delete task locally ────────────────────────────────────
  Future<void> deleteTask(int taskId) async {
    final database = await db;
    await database.delete(
      'tasks',
      where:     'id = ?',
      whereArgs: [taskId],
    );
  }

  // ── Get unsynced tasks ─────────────────────────────────────
  Future<List<TaskModel>> getUnsyncedTasks() async {
    final database = await db;
    final rows     = await database.query(
      'tasks',
      where: 'synced = 0',
    );
    return rows.map(_rowToTask).toList();
  }

  // ── Mark task as synced ────────────────────────────────────
  Future<void> markSynced(int taskId) async {
    final database = await db;
    await database.update(
      'tasks',
      {'synced': 1},
      where:     'id = ?',
      whereArgs: [taskId],
    );
  }

  // ── Queue offline action ───────────────────────────────────
  Future<void> queueAction(String action, int taskId, String payload) async {
    final database = await db;
    await database.insert('pending_actions', {
      'action':  action,
      'task_id': taskId,
      'payload': payload,
    });
  }

  // ── Get pending actions ────────────────────────────────────
  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final database = await db;
    return database.query('pending_actions', orderBy: 'created_at ASC');
  }

  // ── Clear pending action ───────────────────────────────────
  Future<void> clearAction(int id) async {
    final database = await db;
    await database.delete(
      'pending_actions',
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  TaskModel _rowToTask(Map<String, dynamic> row) => TaskModel(
    id:             row['id']             as int,
    name:           row['name']           as String,
    address:        row['address']        as String? ?? '',
    latitude:       row['latitude']       as double,
    longitude:      row['longitude']      as double,
    duration:       row['duration']       as int,
    priority:       row['priority']       as int,
    earliestStart:  row['earliest_start'] as int,
    latestFinish:   row['latest_finish']  as int,
    taskDate:       row['task_date']      as String,
    status:         row['status']         as String,
    isRecurring:    (row['is_recurring']  as int) == 1,
    recurrenceType: row['recurrence_type'] as String?,
    recurrenceDays: row['recurrence_days'] as String?,
  );
}