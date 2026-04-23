"""
Benchmark router — Berlin52 TSP
"""
import math
import time
import asyncio
from fastapi       import APIRouter
from pydantic      import BaseModel
from ..core.models import TaskModel, OptimizationConfig
from ..algorithms.genetic             import run_genetic_algorithm
from ..algorithms.simulated_annealing import run_simulated_annealing
from ..algorithms.ant_colony          import run_ant_colony
from ..algorithms.tabu_search         import run_tabu_search
from ..algorithms.lin_kernighan       import run_lin_kernighan

router = APIRouter()

BERLIN52_COORDS = [
    (565, 575), (25, 185), (345, 750), (945, 685), (845, 655),
    (880, 660), (25, 230), (525, 1000), (580, 1175), (650, 1130),
    (1605, 620), (1220, 580), (1465, 200), (1530, 5), (845, 680),
    (725, 370), (145, 665), (415, 635), (510, 875), (560, 365),
    (300, 465), (520, 585), (480, 415), (835, 625), (975, 580),
    (1215, 245), (1320, 315), (1250, 400), (660, 180), (410, 250),
    (420, 555), (575, 665), (1150, 1160), (700, 580), (685, 595),
    (685, 610), (770, 610), (795, 645), (720, 635), (760, 650),
    (475, 960), (95, 260), (875, 920), (700, 500), (555, 815),
    (830, 485), (1170, 65), (830, 610), (605, 625), (595, 360),
    (1340, 725), (1740, 245),
]

BERLIN52_OPTIMAL = 7542.0

ALGORITHMS = [
    ('genetic',             run_genetic_algorithm),
    ('simulated_annealing', run_simulated_annealing),
    ('ant_colony',          run_ant_colony),
    ('tabu_search',         run_tabu_search),
    ('lin_kernighan',       run_lin_kernighan),
]


class BenchmarkResult(BaseModel):
    algorithm:         str
    tour_length:       float
    optimal_length:    float
    gap_percent:       float
    execution_time_ms: float
    fitness_history:   list[float]


class BenchmarkResponse(BaseModel):
    success:  bool
    results:  list[BenchmarkResult]
    dataset:  str
    n_cities: int
    winner:   str


def _euclidean(a, b):
    return math.sqrt((a[0]-b[0])**2 + (a[1]-b[1])**2)


def _build_matrix(coords):
    n = len(coords)
    m = [[0.0]*(n+1) for _ in range(n+1)]
    for i in range(n):
        for j in range(n):
            if i != j:
                m[i+1][j+1] = _euclidean(coords[i], coords[j])
    return m


def _route_length(route, coords):
    total = 0.0
    for i in range(len(route)-1):
        total += _euclidean(coords[route[i]-1], coords[route[i+1]-1])
    total += _euclidean(coords[route[-1]-1], coords[route[0]-1])
    return total


def _run_benchmark_sync():
    coords = BERLIN52_COORDS
    n      = len(coords)

    tasks = [
        TaskModel(
            id             = i + 1,
            name           = f"City {i+1}",
            latitude       = float(coords[i][0]),
            longitude      = float(coords[i][1]),
            duration       = 0,
            earliest_start = 0,
            latest_finish  = 99999,
            task_date      = "",
        )
        for i in range(n)
    ]

    dist_matrix = _build_matrix(coords)
    config = OptimizationConfig(
        population_size = 50,   # genetik/ACS için yeterli popülasyon
        generations     = 100,  # tüm algoritmalar için yeterli iterasyon
        mutation_rate   = 0.02,
        use_real_roads  = False,
    )

    # ── Parallel çalıştır — 5 algo aynı anda ─────────────────
    from concurrent.futures import ThreadPoolExecutor, as_completed

    def _run_algo(algo_key, algo_fn):
        t0          = time.perf_counter()
        route, hist = algo_fn(tasks, dist_matrix, config)
        elapsed     = (time.perf_counter() - t0) * 1000
        tour_len    = _route_length(route, coords)
        gap         = (tour_len - BERLIN52_OPTIMAL) / BERLIN52_OPTIMAL * 100
        return algo_key, BenchmarkResult(
            algorithm         = algo_key,
            tour_length       = round(tour_len, 2),
            optimal_length    = BERLIN52_OPTIMAL,
            gap_percent       = round(gap, 2),
            execution_time_ms = round(elapsed, 2),
            fitness_history   = hist,
        )

    results    = []
    best_len   = float('inf')
    best_time  = float('inf')
    winner_key = ''

    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {executor.submit(_run_algo, k, fn): k for k, fn in ALGORITHMS}
        for future in as_completed(futures):
            algo_key, result = future.result()
            results.append(result)
            if result.tour_length < best_len or (
                abs(result.tour_length - best_len) < 1.0 and result.execution_time_ms < best_time
            ):
                best_len   = result.tour_length
                best_time  = result.execution_time_ms
                winner_key = algo_key

    # Sonuçları karşılaştırma için sırala
    results.sort(key=lambda r: r.tour_length)

    return BenchmarkResponse(
        success  = True,
        results  = results,
        dataset  = "Berlin52",
        n_cities = n,
        winner   = winner_key,
    )


@router.get("/benchmark/berlin52", response_model=BenchmarkResponse)
async def benchmark_berlin52():
    return await asyncio.get_event_loop().run_in_executor(
        None, _run_benchmark_sync
    )