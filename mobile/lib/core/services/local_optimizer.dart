import 'dart:math' as math;
import '../models/task_model.dart';
import '../models/route_result_model.dart';
import '../models/optimize_request_model.dart';

/// Offline mod — sunucu yokken Flutter tarafında çalışan
/// Nearest Neighbor + 2-opt optimizer.
class LocalOptimizer {

  // ── Haversine mesafe (km) ─────────────────────────────────
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r    = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a    = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  // ── n+1 × n+1 mesafe matrisi (0 = başlangıç) ─────────────
  List<List<double>> _buildMatrix(
      StartLocation start, List<TaskModel> tasks) {
    final lats = [start.latitude,  ...tasks.map((t) => t.latitude)];
    final lons = [start.longitude, ...tasks.map((t) => t.longitude)];
    final n    = lats.length;
    return List.generate(n, (i) =>
        List.generate(n, (j) => i == j
            ? 0.0
            : _haversine(lats[i], lons[i], lats[j], lons[j])));
  }

  // ── Nearest Neighbor: 0'dan başlar, 1..n arası görevler ──
  List<int> _nearestNeighbor(List<List<double>> dist, int n) {
    final visited = List.filled(n + 1, false);
    final route   = <int>[];
    int   current = 0;
    visited[0]    = true;

    for (int step = 0; step < n; step++) {
      double best     = double.infinity;
      int    bestNext = -1;
      for (int j = 1; j <= n; j++) {
        if (!visited[j] && dist[current][j] < best) {
          best     = dist[current][j];
          bestNext = j;
        }
      }
      if (bestNext == -1) break;
      route.add(bestNext);
      visited[bestNext] = true;
      current = bestNext;
    }
    return route;
  }

  // ── 2-opt improvement ─────────────────────────────────────
  List<int> _twoOpt(List<int> route, List<List<double>> dist) {
    final r       = List<int>.from(route);
    bool improved = true;

    while (improved) {
      improved = false;
      for (int i = 0; i < r.length - 1; i++) {
        for (int j = i + 2; j < r.length; j++) {
          final a = i == 0 ? 0 : r[i - 1];
          final b = r[i];
          final c = r[j];
          final d = j + 1 < r.length ? r[j + 1] : 0;

          if (dist[a][b] + dist[c][d] - dist[a][c] - dist[b][d] > 1e-9) {
            // i..j arasını ters çevir
            int lo = i, hi = j;
            while (lo < hi) {
              final tmp = r[lo]; r[lo] = r[hi]; r[hi] = tmp;
              lo++; hi--;
            }
            improved = true;
          }
        }
      }
    }
    return r;
  }

  // ── Ana metod ─────────────────────────────────────────────
  OptimizeResponse optimize(OptimizeRequest request) {
    final tasks = request.tasks.cast<TaskModel>();
    final start = request.startLocation;

    if (tasks.isEmpty) {
      return OptimizeResponse(success: false, error: 'Görev listesi boş.');
    }

    final sw    = Stopwatch()..start();
    final dist  = _buildMatrix(start, tasks);
    final nn    = _nearestNeighbor(dist, tasks.length);
    final route = _twoOpt(nn, dist);
    sw.stop();

    // Toplam mesafe
    double totalDist = dist[0][route.first];
    for (int i = 0; i < route.length - 1; i++) {
      totalDist += dist[route[i]][route[i + 1]];
    }

    // Süre: haversine mesafe / 40 km/h + görev süreleri (dakika)
    double totalTime = (totalDist / 40.0) * 60.0 +
        tasks.fold<double>(0, (s, t) => s + t.duration);

    final ordered = route.map((i) => tasks[i - 1]).toList();

    return OptimizeResponse(
      success: true,
      result:  RouteResult(
        orderedTasks:    ordered,
        totalDistance:   totalDist,
        totalTravelTime: totalTime,
        fitnessScore:    totalDist,
        algorithmUsed:   'offline_nn2opt',
        heuristicUsed:   request.config.heuristic,
        executionTimeMs: sw.elapsedMilliseconds.toDouble(),
        usedRealRoads:   false,
        routeGeometry:   null,
      ),
      comparisonLogs: [],
    );
  }
}