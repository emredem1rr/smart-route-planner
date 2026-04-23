import '../../core/models/task_model.dart';

class RouteResult {
  final List<TaskModel> orderedTasks;
  final double          totalDistance;
  final double          totalTravelTime;
  final double          fitnessScore;
  final String          algorithmUsed;
  final String          heuristicUsed;
  final double          executionTimeMs;
  final bool            usedRealRoads;
  final List<List<double>>? routeGeometry;
  final List<double>?   segmentTimes;   // dakika, her segment için  // [[lat,lon], ...]
  final String?         aiExplanation;  // Gemini rota açıklaması

  RouteResult({
    required this.orderedTasks,
    required this.totalDistance,
    required this.totalTravelTime,
    required this.fitnessScore,
    required this.algorithmUsed,
    required this.heuristicUsed,
    required this.executionTimeMs,
    this.usedRealRoads  = false,
    this.routeGeometry,
    this.segmentTimes,
    this.aiExplanation,
  });

  factory RouteResult.fromJson(Map<String, dynamic> j) => RouteResult(
    orderedTasks    : (j['ordered_tasks'] as List)
        .map((t) => TaskModel.fromJson(t as Map<String, dynamic>))
        .toList(),
    totalDistance   : (j['total_distance']   ?? 0).toDouble(),
    totalTravelTime : (j['total_travel_time'] ?? 0).toDouble(),
    fitnessScore    : (j['fitness_score']     ?? 0).toDouble(),
    algorithmUsed   : j['algorithm_used']     ?? '',
    heuristicUsed   : j['heuristic_used']     ?? '',
    executionTimeMs : (j['execution_time_ms'] ?? 0).toDouble(),
    usedRealRoads   : j['used_real_roads']    ?? false,
    routeGeometry   : j['route_geometry'] != null
        ? (j['route_geometry'] as List)
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList()
        : null,
    segmentTimes    : j['segment_times'] != null
        ? (j['segment_times'] as List)
        .map((v) => (v as num).toDouble()).toList()
        : null,
    aiExplanation   : j['ai_explanation'] as String?,
  );
}

class AlgorithmLog {
  final String       algorithm;
  final double       fitnessScore;
  final double       totalDistance;
  final double       executionTimeMs;
  final List<double> fitnessHistory;

  AlgorithmLog({
    required this.algorithm,
    required this.fitnessScore,
    required this.totalDistance,
    required this.executionTimeMs,
    this.fitnessHistory = const [],
  });

  String get label {
    switch (algorithm) {
      case 'genetic':             return 'Genetik Algoritma';
      case 'simulated_annealing': return 'Simüle Tavlama';
      case 'ant_colony':          return 'Karınca Kolonisi';
      case 'tabu_search':         return 'Tabu Arama';
      case 'lin_kernighan':       return 'Lin-Kernighan';
      default:                    return algorithm;
    }
  }

  factory AlgorithmLog.fromJson(Map<String, dynamic> j) => AlgorithmLog(
    algorithm       : j['algorithm']          ?? '',
    fitnessScore    : (j['fitness_score']      ?? 0).toDouble(),
    totalDistance   : (j['total_distance']     ?? 0).toDouble(),
    executionTimeMs : (j['execution_time_ms']  ?? 0).toDouble(),
    fitnessHistory  : (j['fitness_history'] as List? ?? [])
        .map((v) => (v as num).toDouble())
        .toList(),
  );
}

class OptimizeResponse {
  final bool             success;
  final RouteResult?     result;
  final List<AlgorithmLog> comparisonLogs;
  final String?          error;
  final Map<String, double>? startLocation;

  OptimizeResponse({
    required this.success,
    this.result,
    this.comparisonLogs = const [],
    this.error,
    this.startLocation,
  });

  factory OptimizeResponse.fromJson(Map<String, dynamic> j) => OptimizeResponse(
    success        : j['success'] ?? false,
    result         : j['result'] != null
        ? RouteResult.fromJson(j['result'] as Map<String, dynamic>)
        : null,
    comparisonLogs : (j['comparison_logs'] as List? ?? [])
        .map((l) => AlgorithmLog.fromJson(l as Map<String, dynamic>))
        .toList(),
    error          : j['error'],
    startLocation  : j['start_location'] != null
        ? Map<String, double>.from(j['start_location'])
        : null,
  );
}