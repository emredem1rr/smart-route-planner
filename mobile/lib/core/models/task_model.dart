class TaskModel {
  final int     id;
  final String  name;
  final String  address;
  final double  latitude;
  final double  longitude;
  final int     duration;
  final int     priority;
  final int     earliestStart;
  final int     latestFinish;
  final String  taskDate;
  final String  status;
  final bool    isRecurring;
  final String? recurrenceType;
  final String? recurrenceDays;
  final String? note;           // ← YENİ: görev notu

  TaskModel({
    required this.id,
    required this.name,
    this.address        = '',
    required this.latitude,
    required this.longitude,
    required this.duration,
    required this.priority,
    required this.earliestStart,
    required this.latestFinish,
    required this.taskDate,
    this.status         = 'pending',
    this.isRecurring    = false,
    this.recurrenceType,
    this.recurrenceDays,
    this.note,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    String taskDate = '';
    final rawDate   = json['task_date'];
    if (rawDate != null) {
      if (rawDate.toString().contains('T')) {
        final dt = DateTime.parse(rawDate).toLocal();
        taskDate = '${dt.year}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')}';
      } else {
        taskDate = rawDate.toString();
      }
    }

    return TaskModel(
      id:             json['id']              as int,
      name:           json['name']            as String,
      address:        json['address']         as String?  ?? '',
      latitude:       double.parse(json['latitude'].toString()),
      longitude:      double.parse(json['longitude'].toString()),
      duration:       json['duration']        as int,
      priority:       json['priority']        as int,
      earliestStart:  json['earliest_start']  as int,
      latestFinish:   json['latest_finish']   as int,
      taskDate:       taskDate,
      status:         json['status']          as String?  ?? 'pending',
      isRecurring:    (json['is_recurring']   as int?     ?? 0) == 1,
      recurrenceType: json['recurrence_type'] as String?,
      recurrenceDays: json['recurrence_days'] as String?,
      note:           json['note']            as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':              id,
    'name':            name,
    'address':         address,
    'latitude':        latitude,
    'longitude':       longitude,
    'duration':        duration,
    'priority':        priority,
    'earliest_start':  earliestStart,
    'latest_finish':   latestFinish,
    'task_date':       taskDate,
    'status':          status,
    'is_recurring':    isRecurring ? 1 : 0,
    'recurrence_type': recurrenceType,
    'recurrence_days': recurrenceDays,
    'note':            note,
  };

  TaskModel copyWith({String? status, String? note}) => TaskModel(
    id:             id,
    name:           name,
    address:        address,
    latitude:       latitude,
    longitude:      longitude,
    duration:       duration,
    priority:       priority,
    earliestStart:  earliestStart,
    latestFinish:   latestFinish,
    taskDate:       taskDate,
    status:         status ?? this.status,
    isRecurring:    isRecurring,
    recurrenceType: recurrenceType,
    recurrenceDays: recurrenceDays,
    note:           note ?? this.note,
  );

  String get priorityLabel {
    switch (priority) {
      case 5: return 'Çok Yüksek';
      case 4: return 'Yüksek';
      case 3: return 'Orta';
      case 2: return 'Düşük';
      default: return 'Çok Düşük';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'done':      return 'Yapıldı';
      case 'cancelled': return 'İptal Edildi';
      default:          return 'Bekliyor';
    }
  }

  String get recurrenceLabel {
    switch (recurrenceType) {
      case 'daily':    return 'Her gün';
      case 'weekdays': return 'Hafta içi';
      case 'weekly':   return 'Haftalık';
      default:         return '';
    }
  }

  bool get isPast {
    final now      = DateTime.now();
    final todayStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return taskDate.compareTo(todayStr) < 0;
  }

  bool get isToday {
    final now      = DateTime.now();
    final todayStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return taskDate == todayStr;
  }
}