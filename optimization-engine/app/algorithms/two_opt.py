"""
Lin-Kernighan style 3-opt + 2-opt for TSP
Lin, S. & Kernighan, B.W. (1973). An effective heuristic algorithm for the
traveling-salesman problem. Operations Research, 21(2), 498-516.
Improvements: 3-opt moves, nearest neighbour candidates list,
multiple random restarts with double-bridge perturbation.
"""
import random
from ..core.models  import TaskModel, OptimizationConfig
from ..core.fitness import calculate_fitness


def _build_candidate_list(
    dist_matrix: list[list[float]],
    n:           int,
    k:           int = 5,
) -> list[list[int]]:
    """For each node, keep k nearest neighbours."""
    candidates = []
    for i in range(1, n + 1):
        dists = [(dist_matrix[i][j], j) for j in range(1, n + 1) if j != i]
        dists.sort()
        candidates.append([j for _, j in dists[:k]])
    return candidates


def _two_opt_nn(
    route:       list[int],
    dist_matrix: list[list[float]],
    candidates:  list[list[int]],
    tasks:       list[TaskModel],
    config:      OptimizationConfig,
) -> tuple[list[int], float]:
    """2-opt with candidate list for speed."""
    best     = route[:]
    best_fit = calculate_fitness(best, dist_matrix, tasks, config)
    n        = len(best)
    improved = True

    while improved:
        improved = False
        for idx in range(n):
            i    = best[idx] - 1  # 0-indexed node
            for j_node in candidates[i]:
                j = best.index(j_node)
                if abs(idx - j) < 2:
                    continue
                lo, hi = (idx, j) if idx < j else (j, idx)
                new_route        = best[:]
                new_route[lo:hi+1] = new_route[lo:hi+1][::-1]
                new_fit          = calculate_fitness(new_route, dist_matrix, tasks, config)
                if new_fit < best_fit:
                    best     = new_route
                    best_fit = new_fit
                    improved = True
                    break

    return best, best_fit


def _three_opt_segment(
    route:       list[int],
    dist_matrix: list[list[float]],
    tasks:       list[TaskModel],
    config:      OptimizationConfig,
    max_tries:   int = 20,
) -> list[int]:
    """Partial 3-opt improvement."""
    best     = route[:]
    best_fit = calculate_fitness(best, dist_matrix, tasks, config)
    n        = len(best)

    for _ in range(max_tries):
        i, j, k = sorted(random.sample(range(n), 3))
        # Try all 3-opt reconnections
        segments = [
            best[:i] + best[i:j][::-1] + best[j:k][::-1] + best[k:],
            best[:i] + best[j:k] + best[i:j] + best[k:],
            best[:i] + best[j:k] + best[i:j][::-1] + best[k:],
            best[:i] + best[j:k][::-1] + best[i:j] + best[k:],
        ]
        for seg in segments:
            fit = calculate_fitness(seg, dist_matrix, tasks, config)
            if fit < best_fit:
                best     = seg
                best_fit = fit

    return best


def _double_bridge(route: list[int]) -> list[int]:
    n = len(route)
    if n < 8:
        r = route[:]
        random.shuffle(r)
        return r
    pos = sorted(random.sample(range(1, n), 3))
    a, b, c = pos
    return route[:a] + route[c:] + route[b:c] + route[a:b]


def run_two_opt(
    tasks:       list[TaskModel],
    dist_matrix: list[list[float]],
    config:      OptimizationConfig,
) -> tuple[list[int], list[float]]:
    n          = len(tasks)
    n_restarts = max(8, config.generations // 20)
    candidates = _build_candidate_list(dist_matrix, n, k=min(7, n - 1))
    history    = []

    best_route = None
    best_fit   = float('inf')

    for restart in range(n_restarts):
        if restart == 0:
            # Nearest neighbour initial solution
            visited = [False] * n
            route   = []
            node    = 0
            for _ in range(n):
                nn = min(
                    [j for j in range(n) if not visited[j]],
                    key=lambda j: dist_matrix[node][j + 1],
                )
                visited[nn] = True
                route.append(nn + 1)
                node = nn + 1
        else:
            route = list(range(1, n + 1))
            random.shuffle(route)
            # Perturbation of best found
            if best_route and restart % 2 == 0:
                route = _double_bridge(best_route[:])

        # 2-opt with candidate list
        route, route_fit = _two_opt_nn(route, dist_matrix, candidates, tasks, config)

        # 3-opt improvement
        route     = _three_opt_segment(route, dist_matrix, tasks, config)
        route_fit = calculate_fitness(route, dist_matrix, tasks, config)

        if route_fit < best_fit:
            best_fit   = route_fit
            best_route = route[:]

        history.append(round(best_fit, 6))

    while len(history) < config.generations:
        history.append(round(best_fit, 6))

    return best_route, history[:config.generations]