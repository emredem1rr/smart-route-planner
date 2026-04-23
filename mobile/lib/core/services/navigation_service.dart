import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/task_model.dart';
import 'notification_service.dart';

/// Gerçek zamanlı rota takip servisi
class NavigationService {
  static final NavigationService _i = NavigationService._();
  factory NavigationService() => _i;
  NavigationService._();

  StreamSubscription<Position>? _sub;
  StreamController<NavState>?   _ctrl;

  Stream<NavState>? get stream => _ctrl?.stream;
  bool get active => _sub != null;

  /// Navigasyonu başlat
  Stream<NavState> start(List<TaskModel> tasks) {
    stop();
    _ctrl = StreamController<NavState>.broadcast();

    int currentIdx = 0; // Sıradaki görev index'i

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy:       LocationAccuracy.high,
        distanceFilter: 10, // 10m hareket edince güncelle
      ),
    ).listen((pos) {
      if (currentIdx >= tasks.length) {
        _ctrl?.add(NavState.completed());
        stop();
        return;
      }

      final target  = tasks[currentIdx];
      final distM   = _dist(pos.latitude, pos.longitude,
          target.latitude, target.longitude);
      final distKm  = distM / 1000;
      final etaMin  = distKm / 50 * 60; // 50 km/h varsayım

      // 50m'ye gelince tamamlandı say
      if (distM < 50) {
        NotificationService().showNow(
          id:    target.id + 8000,
          title: '📍 ${target.name} konumundasın!',
          body:  'Görevi tamamla ve sonrakine geç.',
        );
        currentIdx++;
        if (currentIdx >= tasks.length) {
          _ctrl?.add(NavState.completed());
          stop();
          return;
        }
      }

      _ctrl?.add(NavState(
        currentTaskIdx: currentIdx,
        currentTask:    tasks[currentIdx],
        distanceM:      distM,
        etaMinutes:     etaMin,
        userLat:        pos.latitude,
        userLng:        pos.longitude,
        totalTasks:     tasks.length,
        completed:      false,
      ));
    });

    return _ctrl!.stream;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _ctrl?.close();
    _ctrl = null;
  }

  double _dist(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat/2)*sin(dLat/2) +
        cos(lat1*pi/180)*cos(lat2*pi/180)*sin(dLon/2)*sin(dLon/2);
    return R * 2 * atan2(sqrt(a), sqrt(1-a));
  }
}

class NavState {
  final int       currentTaskIdx;
  final TaskModel? currentTask;
  final double    distanceM;
  final double    etaMinutes;
  final double    userLat;
  final double    userLng;
  final int       totalTasks;
  final bool      completed;

  NavState({
    required this.currentTaskIdx,
    required this.currentTask,
    required this.distanceM,
    required this.etaMinutes,
    required this.userLat,
    required this.userLng,
    required this.totalTasks,
    required this.completed,
  });

  factory NavState.completed() => NavState(
    currentTaskIdx: 0,
    currentTask:    null,
    distanceM:      0,
    etaMinutes:     0,
    userLat:        0,
    userLng:        0,
    totalTasks:     0,
    completed:      true,
  );

  String get distanceLabel {
    if (distanceM < 1000) return '${distanceM.toStringAsFixed(0)} m';
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }

  String get etaLabel {
    if (etaMinutes < 1) return '< 1 dk';
    return '${etaMinutes.toStringAsFixed(0)} dk';
  }
}