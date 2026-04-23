import time
import asyncio

from fastapi import APIRouter
from ..core.models              import OptimizeRequest, OptimizeResponse, RouteResult, AlgorithmLog
from ..core.distance_matrix     import build_distance_matrix, build_distance_matrix_async, get_route_geometry
from ..core.fitness             import calculate_fitness, calculate_route_stats
from ..algorithms.genetic             import run_genetic_algorithm
from ..algorithms.simulated_annealing import run_simulated_annealing
from ..algorithms.ant_colony          import run_ant_colony
from ..algorithms.tabu_search         import run_tabu_search
from ..algorithms.lin_kernighan       import run_lin_kernighan

router = APIRouter()

# Gerçek yol için maksimum görev sayısı
# OSRM table API n×n istek yapar — çok büyük matris yavaşlar
REAL_ROADS_MAX_TASKS = 25


async def run_comparison(request: OptimizeRequest) -> OptimizeResponse:
    tasks  = request.tasks
    config = request.config

    if not tasks:
        return OptimizeResponse(success=False, error='Görev listesi boş.')

    use_real = config.use_real_roads and len(tasks) <= REAL_ROADS_MAX_TASKS

    # ── Mesafe matrisi ────────────────────────────────────────
    duration_matrix = None
    if use_real:
        try:
            dist_matrix, duration_matrix = await asyncio.wait_for(
                build_distance_matrix_async(request.start_location, tasks),
                timeout=20.0,
            )
            print(f"[OSRM] Gerçek yol matrisi: {len(tasks)+1}×{len(tasks)+1}")
        except asyncio.TimeoutError:
            print("[OSRM] Timeout — haversine fallback")
            dist_matrix = build_distance_matrix(request.start_location, tasks)
            use_real    = False
        except Exception as e:
            print(f"[OSRM] Hata: {e} — haversine fallback")
            dist_matrix = build_distance_matrix(request.start_location, tasks)
            use_real    = False
    else:
        if config.use_real_roads and len(tasks) > REAL_ROADS_MAX_TASKS:
            print(f"[OSRM] {len(tasks)} görev > {REAL_ROADS_MAX_TASKS} limit — haversine")
        dist_matrix = build_distance_matrix(request.start_location, tasks)

    # ── Algoritma çalıştır ────────────────────────────────────
    results = {}

    def _run(name, fn, *args):
        t0          = time.perf_counter()
        route, hist = fn(*args)
        elapsed     = (time.perf_counter() - t0) * 1000
        stats       = calculate_route_stats(route, dist_matrix, tasks)
        fitness     = calculate_fitness(route, dist_matrix, tasks, config)
        results[name] = {
            'route'            : route,
            'fitness_score'    : fitness,
            'execution_time_ms': elapsed,
            'stats'            : stats,
            'fitness_history'  : hist,
        }

    _run('genetic',             run_genetic_algorithm,   tasks, dist_matrix, config)
    _run('simulated_annealing', run_simulated_annealing, tasks, dist_matrix, config)
    _run('ant_colony',          run_ant_colony,          tasks, dist_matrix, config)
    _run('tabu_search',         run_tabu_search,         tasks, dist_matrix, config)
    _run('lin_kernighan',       run_lin_kernighan,       tasks, dist_matrix, config)

    # ── Kazananı seç ─────────────────────────────────────────
    best_fitness  = min(r['fitness_score'] for r in results.values())
    winner_name, winner = min(
        [(n, r) for n, r in results.items()
         if abs(r['fitness_score'] - best_fitness) < 1e-9],
        key=lambda x: x[1]['execution_time_ms'],
    )

    route = winner['route']

    # ── Süre hesabı ───────────────────────────────────────────
    if duration_matrix:
        total_travel_time  = duration_matrix[0][route[0]]
        for i in range(len(route) - 1):
            total_travel_time += duration_matrix[route[i]][route[i + 1]]
        total_travel_time += sum(tasks[r - 1].duration for r in route)
    else:
        total_travel_time = winner['stats']['total_travel_time']

    # ── Gerçek yol geometrisi (harita için) ───────────────────
    route_geometry = None
    if use_real:
        ordered_locs = (
            [(request.start_location.latitude, request.start_location.longitude)]
            + [(tasks[i - 1].latitude, tasks[i - 1].longitude) for i in route if i > 0]
        )
        try:
            route_geometry = await asyncio.wait_for(
                get_route_geometry(ordered_locs),
                timeout=10.0,
            )
        except Exception:
            route_geometry = None

    ordered_tasks = [tasks[i - 1] for i in route if i > 0]

    # Segment başına seyahat süreleri
    if duration_matrix:
        seg_times = [round(duration_matrix[0][route[0]], 1)]
        for i in range(len(route) - 1):
            seg_times.append(round(duration_matrix[route[i]][route[i+1]], 1))
    else:
        # Haversine mesafeden 50 km/h ile tahmin
        dist_km = winner['stats']['total_distance']
        n_segs  = len(route)
        avg_min = (dist_km / 50.0 * 60.0) / max(n_segs, 1)
        seg_times = [round(avg_min, 1)] * n_segs

    route_result = RouteResult(
        ordered_tasks     = ordered_tasks,
        total_distance    = winner['stats']['total_distance'],
        total_travel_time = total_travel_time,
        fitness_score     = winner['fitness_score'],
        algorithm_used    = winner_name,
        heuristic_used    = config.heuristic,
        execution_time_ms = winner['execution_time_ms'],
        used_real_roads   = use_real,
        route_geometry    = route_geometry,  # [(lat,lon), ...] veya None
        segment_times     = seg_times,
    )

    comparison_logs = [
        AlgorithmLog(
            algorithm         = name,
            fitness_score     = r['fitness_score'],
            total_distance    = r['stats']['total_distance'],
            execution_time_ms = r['execution_time_ms'],
            fitness_history   = r['fitness_history'],
        )
        for name, r in results.items()
    ]

    return OptimizeResponse(
        success         = True,
        result          = route_result,
        comparison_logs = comparison_logs,
    )


@router.post('/optimize', response_model=OptimizeResponse)
async def optimize_route(request: OptimizeRequest) -> OptimizeResponse:
    return await run_comparison(request)