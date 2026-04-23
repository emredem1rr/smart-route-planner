import time

from ..core.models              import OptimizeRequest, OptimizeResponse, RouteResult, AlgorithmLog
from ..core.distance_matrix     import build_distance_matrix, build_distance_matrix_async
from ..core.fitness             import calculate_fitness, calculate_route_stats
from ..algorithms.genetic             import run_genetic_algorithm
from ..algorithms.simulated_annealing import run_simulated_annealing
from ..algorithms.ant_colony          import run_ant_colony
from ..algorithms.tabu_search         import run_tabu_search
from ..algorithms.lin_kernighan       import run_lin_kernighan

async def run_comparison(request: OptimizeRequest) -> OptimizeResponse:
    tasks  = request.tasks
    config = request.config

    if not tasks:
        return OptimizeResponse(success=False, error='Görev listesi boş.')

    if config.use_real_roads and len(tasks) <= 20:
        try:
            dist_matrix, duration_matrix = await build_distance_matrix_async(
                request.start_location, tasks
            )
        except Exception:
            dist_matrix     = build_distance_matrix(request.start_location, tasks)
            duration_matrix = None
    else:
        dist_matrix     = build_distance_matrix(request.start_location, tasks)
        duration_matrix = None

    results = {}

    def _run(name, fn, *args):
        t0          = time.perf_counter()
        route, hist = fn(*args)
        elapsed     = (time.perf_counter() - t0) * 1000
        stats       = calculate_route_stats(route, dist_matrix, tasks)
        fitness     = calculate_fitness(route, dist_matrix, tasks, config)
        results[name] = {
            'route':             route,
            'fitness_score':     fitness,
            'execution_time_ms': elapsed,
            'stats':             stats,
            'fitness_history':   hist,
        }

    _run('genetic',             run_genetic_algorithm,   tasks, dist_matrix, config)
    _run('simulated_annealing', run_simulated_annealing, tasks, dist_matrix, config)
    _run('ant_colony',          run_ant_colony,          tasks, dist_matrix, config)
    _run('tabu_search',         run_tabu_search,         tasks, dist_matrix, config)
    _run('lin_kernighan', run_lin_kernighan, tasks, dist_matrix, config)

    best_fitness    = min(r['fitness_score'] for r in results.values())
    winner_name, winner = min(
        [(n, r) for n, r in results.items()
         if abs(r['fitness_score'] - best_fitness) < 1e-9],
        key=lambda x: x[1]['execution_time_ms'],
    )

    total_travel_time = (
        sum(duration_matrix[winner['route'][i]][winner['route'][i+1]]
            for i in range(len(winner['route']) - 1))
        if duration_matrix
        else winner['stats']['total_travel_time']
    )

    ordered_tasks = [tasks[i - 1] for i in winner['route'] if i > 0]
    print(f"[DEBUG] total_travel_time: {total_travel_time}")
    print(f"[DEBUG] total_distance: {winner['stats']['total_distance']}")
    print(f"[DEBUG] route: {winner['route']}")
    route_result = RouteResult(
        ordered_tasks     = ordered_tasks,
        total_distance    = winner['stats']['total_distance'],
        total_travel_time = total_travel_time,
        fitness_score     = winner['fitness_score'],
        algorithm_used    = winner_name,
        heuristic_used    = config.heuristic,
        execution_time_ms = winner['execution_time_ms'],
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