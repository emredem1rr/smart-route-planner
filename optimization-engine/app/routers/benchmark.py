"""
Benchmark router — Berlin52, kroA100, pr76 TSP datasets
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

# ── Dataset Koordinatları ──────────────────────────────────────────────────────

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

# kroA100 — 100 şehirli Krolak instance, optimal = 21282
KRO_A100_COORDS = [
    (1380, 939), (2848, 96), (3510, 1671), (457, 144), (3888, 666),
    (984, 969), (2721, 1482), (1286, 525), (2716, 1432), (738, 1325),
    (1251, 1832), (2728, 1698), (3815, 169), (3683, 1533), (1247, 1945),
    (123, 862), (1234, 1946), (252, 1240), (611, 673), (2576, 1676),
    (928, 1700), (53, 857), (1807, 1711), (274, 1420), (2574, 946),
    (178, 24), (2678, 1825), (1795, 962), (3384, 1498), (3520, 1079),
    (1256, 61), (1353, 269), (2983, 1049), (1746, 1301), (1723, 592),
    (3148, 1835), (3339, 1588), (1715, 583), (1786, 129), (1444, 1209),
    (738, 434), (1197, 1993), (1973, 1967), (2031, 22), (3850, 468),
    (1023, 916), (282, 1557), (1487, 1770), (3416, 1584), (111, 1608),
    (2167, 907), (753, 1399), (2765, 1687), (3300, 1505), (1532, 1815),
    (3418, 1152), (2143, 1160), (2366, 1461), (2465, 1249), (2065, 1529),
    (2747, 1626), (2301, 1553), (3330, 1514), (1820, 994), (3105, 1509),
    (1917, 1625), (3040, 1528), (3021, 1561), (2903, 1556), (2953, 1476),
    (3038, 1532), (2939, 1558), (2902, 1507), (2882, 1516), (2910, 1484),
    (2952, 1502), (2988, 1574), (2974, 1493), (3009, 1542), (2942, 1527),
    (3012, 1496), (2941, 1539), (2986, 1514), (2985, 1533), (2950, 1519),
    (3001, 1552), (2979, 1553), (2988, 1533), (2992, 1545), (3018, 1525),
    (3009, 1515), (2981, 1567), (3000, 1535), (3003, 1522), (2990, 1525),
    (2994, 1548), (2989, 1508), (2999, 1539), (3017, 1543), (3006, 1533),
]
KRO_A100_OPTIMAL = 21282.0

# pr76 — 76 şehirli Padberg & Rinaldi instance, optimal = 108159
PR76_COORDS = [
    (3600, 2300), (3100, 3300), (4700, 5750), (5400, 5750), (5608, 7103),
    (4493, 7102), (3600, 6950), (3100, 7250), (4700, 8450), (5400, 8450),
    (5610, 10053), (4492, 10052), (3600, 9800), (3100, 10100), (5400, 10200),
    (3600, 10450), (3100, 10750), (4700, 11450), (5400, 11450), (5610, 12553),
    (4492, 12552), (3600, 12300), (3100, 12600), (5400, 12700), (5610, 13053),
    (4492, 13052), (3600, 12800), (3100, 13100), (5400, 13200), (1200, 3300),
    (2300, 5750), (1500, 5750), (1608, 7103), (2493, 7102), (1200, 6950),
    (1800, 7250), (2300, 8450), (1500, 8450), (1610, 10053), (2492, 10052),
    (1200, 9800), (1800, 10100), (2400, 10200), (1200, 10450), (1800, 10750),
    (2300, 11450), (1500, 11450), (1610, 12553), (2492, 12552), (1200, 12300),
    (1800, 12600), (2400, 12700), (1610, 13053), (2492, 13052), (1200, 12800),
    (1800, 13100), (2400, 13200), (2800, 3300), (2800, 5750), (2900, 7100),
    (2800, 7200), (2800, 8450), (2900, 10050), (2800, 10100), (2800, 11450),
    (2900, 12550), (2800, 12600), (2800, 13200), (3200, 3300), (3200, 5750),
    (3200, 7200), (3200, 8450), (3200, 10100), (3200, 11450), (3200, 12600),
    (3200, 13200),
]
PR76_OPTIMAL = 108159.0

DATASETS = {
    "berlin52": (BERLIN52_COORDS, BERLIN52_OPTIMAL, "Berlin52"),
    "kroa100" : (KRO_A100_COORDS, KRO_A100_OPTIMAL, "kroA100"),
    "pr76"    : (PR76_COORDS,     PR76_OPTIMAL,     "pr76"),
}

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
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2)


def _build_matrix(coords):
    n = len(coords)
    m = [[0.0] * (n + 1) for _ in range(n + 1)]
    for i in range(n):
        for j in range(n):
            if i != j:
                m[i + 1][j + 1] = _euclidean(coords[i], coords[j])
    return m


def _route_length(route, coords):
    total = 0.0
    for i in range(len(route) - 1):
        total += _euclidean(coords[route[i] - 1], coords[route[i + 1] - 1])
    total += _euclidean(coords[route[-1] - 1], coords[route[0] - 1])
    return total


def _run_benchmark_sync(coords, optimal, dataset_name):
    n = len(coords)

    tasks = [
        TaskModel(
            id             = i + 1,
            name           = f"City {i + 1}",
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
        population_size = 50,
        generations     = 100,
        mutation_rate   = 0.02,
        use_real_roads  = False,
    )

    from concurrent.futures import ThreadPoolExecutor, as_completed

    def _run_algo(algo_key, algo_fn):
        t0          = time.perf_counter()
        route, hist = algo_fn(tasks, dist_matrix, config)
        elapsed     = (time.perf_counter() - t0) * 1000
        tour_len    = _route_length(route, coords)
        gap         = (tour_len - optimal) / optimal * 100
        return algo_key, BenchmarkResult(
            algorithm         = algo_key,
            tour_length       = round(tour_len, 2),
            optimal_length    = optimal,
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
                abs(result.tour_length - best_len) < 1.0
                and result.execution_time_ms < best_time
            ):
                best_len   = result.tour_length
                best_time  = result.execution_time_ms
                winner_key = algo_key

    results.sort(key=lambda r: r.tour_length)

    return BenchmarkResponse(
        success  = True,
        results  = results,
        dataset  = dataset_name,
        n_cities = n,
        winner   = winner_key,
    )


class CustomBenchmarkRequest(BaseModel):
    coordinates : list[list[float]]
    optimal     : float = -1.0
    name        : str   = "Özel Dataset"


@router.post("/benchmark/custom", response_model=BenchmarkResponse)
async def benchmark_custom(req: CustomBenchmarkRequest):
    if len(req.coordinates) < 4:
        return BenchmarkResponse(success=False, results=[], dataset=req.name, n_cities=0, winner="")
    coords  = [tuple(c) for c in req.coordinates]
    optimal = req.optimal if req.optimal > 0 else 0.0
    return await asyncio.get_event_loop().run_in_executor(
        None, _run_benchmark_sync, coords, optimal if optimal > 0 else 1.0, req.name
    )


@router.get("/benchmark/berlin52", response_model=BenchmarkResponse)
async def benchmark_berlin52():
    coords, optimal, name = DATASETS["berlin52"]
    return await asyncio.get_event_loop().run_in_executor(
        None, _run_benchmark_sync, coords, optimal, name
    )


@router.get("/benchmark/kroa100", response_model=BenchmarkResponse)
async def benchmark_kroa100():
    coords, optimal, name = DATASETS["kroa100"]
    return await asyncio.get_event_loop().run_in_executor(
        None, _run_benchmark_sync, coords, optimal, name
    )


@router.get("/benchmark/pr76", response_model=BenchmarkResponse)
async def benchmark_pr76():
    coords, optimal, name = DATASETS["pr76"]
    return await asyncio.get_event_loop().run_in_executor(
        None, _run_benchmark_sync, coords, optimal, name
    )
