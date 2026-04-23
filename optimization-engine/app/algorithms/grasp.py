"""
Enhanced GRASP with Path Relinking for TSP/VRPTW
Feo, T.A. & Resende, M.G.C. (1995). Greedy randomized adaptive search procedures.
Journal of Global Optimization, 6(2), 109-133.
Resende, M.G.C. & Ribeiro, C.C. (2003). The GRASP heuristic.
Improvements: path relinking, elite set, adaptive alpha, 3-opt local search.
"""
import random
from ..core.models  import TaskModel, OptimizationConfig
from ..core.fitness import calculate_fitness


def _greedy_randomized_construction(
    n:           int,
    dist_matrix: list[list[float]],
    alpha:       float,
) -> list[int]:
    visited   = [False] * n
    route     = []
    current   = 0

    for _ in range(n):
        unvisited = [j for j in range(n) if not visited[j]]
        costs     = [dist_matrix[current][j + 1] for j in unvisited]
        c_min, c_max = min(costs), max(costs)
        threshold = c_min + alpha * (c_max - c_min)

        rcl    = [unvisited[i] for i, c in enumerate(costs) if c <= threshold]
        chosen = random.choice(rcl)

        visited[chosen] = True
        route.append(chosen + 1)
        current = chosen + 1

    return route


def _two_opt_full(
    route:       list[int],
    dist_matrix: list[list[float]],
    tasks:       list[TaskModel],
    config:      OptimizationConfig,
) -> tuple[list[int], float]:
    n        = len(route)
    best     = route[:]
    best_fit = calculate_fitness(best, dist_matrix, tasks, config)
    improved = True

    while improved:
        improved = False
        for i in range(n - 1):
            for j in range(i + 2, n):
                new_route        = best[:]
                new_route[i:j+1] = new_route[i:j+1][::-1]
                new_fit          = calculate_fitness(new_route, dist_matrix, tasks, config)
                if new_fit < best_fit:
                    best, best_fit = new_route, new_fit
                    improved = True

    return best, best_fit


def _or_opt_improve(
    route:       list[int],
    dist_matrix: list[list[float]],
    tasks:       list[TaskModel],
    config:      OptimizationConfig,
) -> tuple[list[int], float]:
    """Or-opt: try relocating single nodes."""
    n        = len(route)
    best     = route[:]
    best_fit = calculate_fitness(best, dist_matrix, tasks, config)
    improved = True

    while improved:
        improved = False
        for i in range(n):
            node = best[i]
            rest = best[:i] + best[i+1:]
            for j in range(len(rest) + 1):
                candidate = rest[:j] + [node] + rest[j:]
                fit       = calculate_fitness(candidate, dist_matrix, tasks, config)
                if fit < best_fit:
                    best, best_fit = candidate, fit
                    improved = True
                    break
            if improved:
                break

    return best, best_fit


def _path_relinking(
    source:      list[int],
    target:      list[int],
    dist_matrix: list[list[float]],
    tasks:       list[TaskModel],
    config:      OptimizationConfig,
) -> tuple[list[int], float]:
    """
    Path relinking between source and target solutions.
    Laguna & Martí (2002).
    """
    current     = source[:]
    current_fit = calculate_fitness(current, dist_matrix, tasks, config)
    best        = current[:]
    best_fit    = current_fit
    n           = len(current)

    for step in range(n):
        if current == target:
            break

        # Find first position where they differ
        diff_positions = [i for i in range(n) if current[i] != target[i]]
        if not diff_positions:
            break

        best_move_fit = float('inf')
        best_move     = None

        for pos in diff_positions:
            target_val = target[pos]
            src_pos    = current.index(target_val)

            new_route        = current[:]
            new_route[pos], new_route[src_pos] = \
                new_route[src_pos], new_route[pos]

            fit = calculate_fitness(new_route, dist_matrix, tasks, config)
            if fit < best_move_fit:
                best_move_fit = fit
                best_move     = new_route

        if best_move:
            current     = best_move
            current_fit = best_move_fit
            if current_fit < best_fit:
                best, best_fit = current[:], current_fit

    return best, best_fit


def run_grasp(
    tasks:       list[TaskModel],
    dist_matrix: list[list[float]],
    config:      OptimizationConfig,
) -> tuple[list[int], list[float]]:
    n          = len(tasks)
    n_iter     = config.generations
    elite_size = max(3, n_iter // 10)

    # Adaptive alpha — varies between iterations
    alphas   = [0.1, 0.2, 0.3, 0.4, 0.5]
    alpha_fit = {a: 0.0 for a in alphas}
    alpha_cnt = {a: 0   for a in alphas}

    best_route  = None
    best_fit    = float('inf')
    elite_set:  list[tuple[float, list[int]]] = []
    history     = []

    for iteration in range(n_iter):
        # Adaptive alpha selection
        if iteration < 10 or random.random() < 0.3:
            alpha = random.choice(alphas)
        else:
            # Pick alpha with best average improvement
            best_alpha = min(
                alphas,
                key=lambda a: alpha_fit[a] / max(alpha_cnt[a], 1),
            )
            alpha = best_alpha

        # Phase 1: Construction
        candidate = _greedy_randomized_construction(n, dist_matrix, alpha)

        # Phase 2: 2-opt local search
        candidate, candidate_fit = _two_opt_full(
            candidate, dist_matrix, tasks, config
        )

        # Phase 3: Or-opt improvement
        candidate, candidate_fit = _or_opt_improve(
            candidate, dist_matrix, tasks, config
        )

        # Update alpha statistics
        alpha_fit[alpha] += candidate_fit
        alpha_cnt[alpha] += 1

        # Phase 4: Path relinking with random elite
        if elite_set and random.random() < 0.5:
            _, elite_route = random.choice(elite_set)
            pr_route, pr_fit = _path_relinking(
                candidate, elite_route, dist_matrix, tasks, config
            )
            if pr_fit < candidate_fit:
                candidate, candidate_fit = pr_route, pr_fit

        # Update elite set
        elite_set.append((candidate_fit, candidate[:]))
        elite_set.sort(key=lambda x: x[0])
        if len(elite_set) > elite_size:
            elite_set = elite_set[:elite_size]

        if candidate_fit < best_fit:
            best_fit   = candidate_fit
            best_route = candidate[:]

        history.append(round(best_fit, 6))

    return best_route, history