class StartLocation {
  final double latitude;
  final double longitude;

  StartLocation({required this.latitude, required this.longitude});

  Map<String, dynamic> toJson() => {
    'latitude' : latitude,
    'longitude': longitude,
  };
}

class OptimizationConfig {
  final String heuristic;
  final int    populationSize;
  final int    generations;
  final double mutationRate;
  final double saInitialTemp;
  final double saCoolingRate;
  final bool   useRealRoads;
  final bool   useTraffic;

  OptimizationConfig({
    this.heuristic      = 'euclidean',
    this.populationSize = 100,
    this.generations    = 200,
    this.mutationRate   = 0.02,
    this.saInitialTemp  = 1000.0,
    this.saCoolingRate  = 0.995,
    this.useRealRoads   = true,
    this.useTraffic     = false,
  });

  Map<String, dynamic> toJson() => {
    'heuristic'       : heuristic,
    'population_size' : populationSize,
    'generations'     : generations,
    'mutation_rate'   : mutationRate,
    'sa_initial_temp' : saInitialTemp,
    'sa_cooling_rate' : saCoolingRate,
    'use_real_roads'  : useRealRoads,
    'use_traffic'     : useTraffic,
  };
}

class OptimizeRequest {
  final StartLocation      startLocation;
  final List<dynamic>      tasks;
  final OptimizationConfig config;

  OptimizeRequest({
    required this.startLocation,
    required this.tasks,
    required this.config,
  });

  Map<String, dynamic> toJson() => {
    'start_location': startLocation.toJson(),
    'tasks'         : tasks.map((t) => t.toJson()).toList(),
    'config'        : config.toJson(),
  };
}