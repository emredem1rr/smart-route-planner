import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/task_model.dart';
import 'notification_service.dart';

/// Konum bazlı görev hatırlatıcı
/// Kullanıcı bir göreve yaklaştığında bildirim gönderir
class GeofenceService {
  static final GeofenceService _i = GeofenceService._();
  factory GeofenceService() => _i;
  GeofenceService._();

  static const double _triggerRadiusMeters = 500; // 500m yaklaşınca tetikle
  final Set<int> _notified = {}; // Aynı gün tekrar bildirme
  bool _running = false;

  /// Konum takibini başlat
  void start(List<TaskModel> tasks) {
    if (_running) return;
    _running = true;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy:       LocationAccuracy.medium,
        distanceFilter: 50, // 50m hareket edince kontrol et
      ),
    ).listen((pos) => _check(pos, tasks));
  }

  void stop() => _running = false;

  /// Görevlere olan mesafeyi kontrol et
  void _check(Position pos, List<TaskModel> tasks) {
    final today = _todayStr();

    for (final task in tasks) {
      if (task.status != 'pending') continue;
      if (task.taskDate != today)   continue;
      if (_notified.contains(task.id)) continue;

      final dist = _distanceMeters(
        pos.latitude, pos.longitude,
        task.latitude, task.longitude,
      );

      if (dist <= _triggerRadiusMeters) {
        _notified.add(task.id);
        NotificationService().showNow(
          title:   '📍 ${task.name} durağına yaklaşıyorsunuz',
          body:    '${dist.toStringAsFixed(0)}m uzakta'
              '${task.address.isNotEmpty ? " — ${task.address}" : ""}',
          id:      task.id + 9000,
          type:    'geofence',
          payload: 'route',
        );
      }
    }
  }

  /// Haversine formülü ile metre cinsinden mesafe
  double _distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  /// Yeni gün gelince notified setini temizle
  void clearDaily() => _notified.clear();
}