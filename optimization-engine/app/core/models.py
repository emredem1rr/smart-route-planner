from pydantic import BaseModel
from typing   import Optional


class TaskModel(BaseModel):
    id:             int
    name:           str
    address:        str   = ""
    latitude:       float
    longitude:      float
    duration:       int
    priority:       int   = 3
    earliest_start: int   = 0
    latest_finish:  int   = 480
    task_date:      str   = ""
    status:         str   = "pending"

    @property
    def priority_label(self) -> str:
        labels = {5: "Çok Yüksek", 4: "Yüksek", 3: "Orta", 2: "Düşük", 1: "Çok Düşük"}
        return labels.get(self.priority, "Orta")


class StartLocation(BaseModel):
    latitude:  float
    longitude: float


class OptimizationConfig(BaseModel):
    heuristic:       str   = "euclidean"
    population_size: int   = 100
    generations:     int   = 200
    mutation_rate:   float = 0.02
    sa_initial_temp: float = 1000.0
    sa_cooling_rate: float = 0.995
    use_real_roads:  bool  = True


class OptimizeRequest(BaseModel):
    start_location: StartLocation
    tasks:          list[TaskModel]
    config:         OptimizationConfig = OptimizationConfig()


class RouteResult(BaseModel):
    ordered_tasks:     list[TaskModel]
    total_distance:    float
    total_travel_time: float
    fitness_score:     float
    algorithm_used:    str
    heuristic_used:    str
    execution_time_ms: float
    used_real_roads:   bool                              = False
    route_geometry:    Optional[list[list[float]]]       = None  # [[lat,lon], ...]
    segment_times:     Optional[list[float]]             = None  # dakika cinsinden her segment


class AlgorithmLog(BaseModel):
    algorithm:         str
    fitness_score:     float
    total_distance:    float
    execution_time_ms: float
    fitness_history:   list[float] = []


class OptimizeResponse(BaseModel):
    success:         bool
    result:          Optional[RouteResult] = None
    comparison_logs: list[AlgorithmLog]   = []
    error:           Optional[str]        = None