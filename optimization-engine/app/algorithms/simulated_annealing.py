"""
Simulated Annealing — ILS tabanlı
Double bridge perturbation + 2-opt local search
Her restart'ta farklı başlangıç → yerel optimumlardan kaçış
"""
import random
import math
from ..core.models  import TaskModel, OptimizationConfig
from ..core.fitness import calculate_fitness, route_distance, get_max_dist


def _nn(n, dist_matrix):
    visited = [False]*n
    route, node = [], 0
    for _ in range(n):
        best_d, best_j = float('inf'), -1
        for j in range(n):
            if not visited[j] and dist_matrix[node][j+1] < best_d:
                best_d, best_j = dist_matrix[node][j+1], j
        visited[best_j] = True
        route.append(best_j+1)
        node = best_j+1
    return route


def _two_opt(route, dist_matrix):
    best, best_d = route[:], route_distance(route, dist_matrix)
    improved = True
    while improved:
        improved = False
        for i in range(len(best)-1):
            for j in range(i+2, len(best)):
                new_r = best[:]
                new_r[i:j+1] = new_r[i:j+1][::-1]
                new_d = route_distance(new_r, dist_matrix)
                if new_d < best_d:
                    best, best_d = new_r, new_d
                    improved = True
    return best, best_d


def _or_opt_pass(route, dist_matrix):
    """Tek geçiş or-opt iyileştirme."""
    best, best_d = route[:], route_distance(route, dist_matrix)
    n = len(best)
    improved = True
    while improved:
        improved = False
        for i in range(n):
            node = best[i]
            rest = best[:i] + best[i+1:]
            for j in range(len(rest)+1):
                if abs(j-i) <= 1:
                    continue
                new_r = rest[:j] + [node] + rest[j:]
                new_d = route_distance(new_r, dist_matrix)
                if new_d < best_d:
                    best, best_d = new_r, new_d
                    improved = True
                    break
            if improved:
                break
    return best, best_d


def _double_bridge(route):
    n = len(route)
    if n < 8:
        r = route[:]
        random.shuffle(r)
        return r
    a, b, c = sorted(random.sample(range(1, n), 3))
    return route[:a] + route[c:] + route[b:c] + route[a:b]


def _local_search(route, dist_matrix):
    """2-opt + or-opt lokal arama."""
    r, d = _two_opt(route, dist_matrix)
    r, d = _or_opt_pass(r, dist_matrix)
    return r, d


def run_simulated_annealing(
    tasks:       list[TaskModel],
    dist_matrix: list[list[float]],
    config:      OptimizationConfig,
) -> tuple[list[int], list[float]]:
    n         = len(tasks)
    max_dist  = get_max_dist(dist_matrix)
    n_restarts = config.generations  # 100 restart
    history   = []

    # İlk çözüm: NN + lokal arama
    current, current_d = _local_search(_nn(n, dist_matrix), dist_matrix)
    best, best_d       = current[:], current_d
    history.append(round(
        calculate_fitness(best, dist_matrix, tasks, config, max_dist), 6))

    print(f"[SA/ILS] başlangıç={current_d:.1f}, restarts={n_restarts}")

    for restart in range(n_restarts - 1):
        # Double bridge perturb → lokal arama
        perturbed        = _double_bridge(best[:])
        new_r, new_d     = _local_search(perturbed, dist_matrix)

        if new_d < best_d:
            best, best_d = new_r, new_d

        if (restart + 1) % (n_restarts // config.generations + 1) == 0:
            fit = calculate_fitness(best, dist_matrix, tasks, config, max_dist)
            history.append(round(fit, 6))

    while len(history) < config.generations:
        history.append(history[-1] if history else 0.0)

    print(f"[SA/ILS] sonuç={best_d:.1f}")
    return best, history[:config.generations]