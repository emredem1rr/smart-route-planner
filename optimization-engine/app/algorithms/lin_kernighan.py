"""
Lin-Kernighan Heuristic for TSP
Lin & Kernighan (1973) — en iyi bilinen TSP heuristiği.
3-opt moves + Or-opt refinement.
"""
import random
from ..core.models  import TaskModel, OptimizationConfig
from ..core.fitness import calculate_fitness, get_max_dist


def _nearest_neighbour(n, dist_matrix):
    visited = [False] * n
    route   = []
    node    = 0
    for _ in range(n):
        best_d = float('inf')
        best_j = -1
        for j in range(n):
            if not visited[j] and dist_matrix[node][j+1] < best_d:
                best_d = dist_matrix[node][j+1]
                best_j = j
        visited[best_j] = True
        route.append(best_j + 1)
        node = best_j + 1
    return route


def _two_opt_pass(route, dist_matrix, tasks, config, max_dist):
    best     = route[:]
    best_fit = calculate_fitness(best, dist_matrix, tasks, config, max_dist)
    improved = True
    while improved:
        improved = False
        for i in range(len(best) - 1):
            for j in range(i + 2, len(best)):
                new_route        = best[:]
                new_route[i:j+1] = new_route[i:j+1][::-1]
                new_fit          = calculate_fitness(new_route, dist_matrix, tasks, config, max_dist)
                if new_fit < best_fit:
                    best     = new_route
                    best_fit = new_fit
                    improved = True
    return best, best_fit


def _or_opt_pass(route, dist_matrix, tasks, config, max_dist):
    """1, 2 ve 3 node segment relocate."""
    best     = route[:]
    best_fit = calculate_fitness(best, dist_matrix, tasks, config, max_dist)
    improved = True
    while improved:
        improved = False
        n = len(best)
        for seg_len in [1, 2, 3]:
            for i in range(n - seg_len + 1):
                segment   = best[i:i+seg_len]
                remaining = best[:i] + best[i+seg_len:]
                for j in range(len(remaining) + 1):
                    new_route = remaining[:j] + segment + remaining[j:]
                    if new_route == best:
                        continue
                    new_fit = calculate_fitness(new_route, dist_matrix, tasks, config, max_dist)
                    if new_fit < best_fit:
                        best     = new_route
                        best_fit = new_fit
                        improved = True
    return best, best_fit


def _double_bridge(route):
    """4-opt double bridge — lokal optimumdan kaçmak için."""
    n = len(route)
    if n < 8:
        r = route[:]
        random.shuffle(r)
        return r
    pos    = sorted(random.sample(range(1, n), 3))
    a, b, c = pos
    return route[:a] + route[c:] + route[b:c] + route[a:b]


def run_lin_kernighan(
    tasks:       list[TaskModel],
    dist_matrix: list[list[float]],
    config:      OptimizationConfig,
) -> tuple[list[int], list[float]]:
    n        = len(tasks)
    max_dist = get_max_dist(dist_matrix)
    n_iter   = config.generations
    history  = []

    # Birden fazla başlangıç noktası dene
    n_starts  = max(3, config.population_size // 10)
    best_route = _nearest_neighbour(n, dist_matrix)
    best_fit   = calculate_fitness(best_route, dist_matrix, tasks, config, max_dist)

    for start in range(n_starts):
        if start == 0:
            route = _nearest_neighbour(n, dist_matrix)
        else:
            route = list(range(1, n+1))
            random.shuffle(route)

        # 2-opt
        route, fit = _two_opt_pass(route, dist_matrix, tasks, config, max_dist)

        # Or-opt
        route, fit = _or_opt_pass(route, dist_matrix, tasks, config, max_dist)

        if fit < best_fit:
            best_fit   = fit
            best_route = route[:]

    # Perturbation + re-optimization döngüsü
    current      = best_route[:]
    current_fit  = best_fit
    no_improve   = 0

    for iteration in range(n_iter):
        # Double bridge perturbation
        perturbed     = _double_bridge(current)
        perturbed, fit = _two_opt_pass(perturbed, dist_matrix, tasks, config, max_dist)
        perturbed, fit = _or_opt_pass(perturbed, dist_matrix, tasks, config, max_dist)

        if fit < current_fit:
            current     = perturbed
            current_fit = fit
            no_improve  = 0
        else:
            no_improve += 1

        if fit < best_fit:
            best_fit   = fit
            best_route = current[:]

        # Çok uzun takılırsa yeni rastgele başlangıç
        if no_improve > n_iter // 5:
            route = list(range(1, n+1))
            random.shuffle(route)
            route, fit  = _two_opt_pass(route, dist_matrix, tasks, config, max_dist)
            current     = route
            current_fit = fit
            no_improve  = 0

        history.append(round(best_fit, 6))

    return best_route, history[:n_iter]