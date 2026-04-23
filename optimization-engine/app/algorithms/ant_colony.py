"""
Ant Colony System (ACS) for TSP
Dorigo & Gambardella (1997).
"""
import random
from ..core.models  import TaskModel, OptimizationConfig
from ..core.fitness import calculate_fitness, get_max_dist


def run_ant_colony(
    tasks:       list[TaskModel],
    dist_matrix: list[list[float]],
    config:      OptimizationConfig,
) -> tuple[list[int], list[float]]:
    n        = len(tasks)
    n_ants   = min(config.population_size, 20)
    n_iter   = config.generations
    alpha    = 1.0
    beta     = 3.0
    rho      = 0.1
    phi      = 0.1
    q0       = 0.9
    tau0     = 1.0 / (n * _avg_dist(dist_matrix, n))
    max_dist = get_max_dist(dist_matrix)

    tau = [[tau0] * (n + 1) for _ in range(n + 1)]
    eta = [[0.0]  * (n + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        for j in range(n + 1):
            d         = dist_matrix[i][j] if i != j else float('inf')
            eta[i][j] = 1.0 / max(d, 1e-10)

    best_route = None
    best_fit   = float('inf')
    history    = []

    for iteration in range(n_iter):
        all_routes = []

        for ant in range(n_ants):
            visited = [False] * n
            route   = []
            current = 0

            for step in range(n):
                unvisited = [j for j in range(n) if not visited[j]]
                q         = random.random()

                if q <= q0:
                    chosen = max(
                        unvisited,
                        key=lambda j: tau[current][j+1] * (eta[current][j+1] ** beta)
                    )
                else:
                    probs = [
                        (tau[current][j+1] ** alpha) * (eta[current][j+1] ** beta)
                        for j in unvisited
                    ]
                    total = sum(probs)
                    if total == 0:
                        chosen = random.choice(unvisited)
                    else:
                        r      = random.random() * total
                        acc    = 0.0
                        chosen = unvisited[-1]
                        for idx, p in enumerate(probs):
                            acc += p
                            if r <= acc:
                                chosen = unvisited[idx]
                                break

                tau[current][chosen+1] = (1-phi) * tau[current][chosen+1] + phi * tau0
                tau[chosen+1][current] = tau[current][chosen+1]
                visited[chosen] = True
                route.append(chosen + 1)
                current = chosen + 1

            all_routes.append(route)

        all_fits        = [calculate_fitness(r, dist_matrix, tasks, config, max_dist) for r in all_routes]
        iter_best_idx   = min(range(len(all_fits)), key=lambda i: all_fits[i])
        iter_best_route = all_routes[iter_best_idx]
        iter_best_fit   = all_fits[iter_best_idx]

        if iter_best_fit < best_fit:
            best_fit   = iter_best_fit
            best_route = iter_best_route[:]

        history.append(round(best_fit, 6))

        for i in range(n + 1):
            for j in range(n + 1):
                tau[i][j] = max(tau[i][j] * (1 - rho), tau0 * 0.1)

        deposit = 1.0 / max(best_fit, 1e-10)
        prev    = 0
        for node in best_route:
            tau[prev][node] = (1-rho) * tau[prev][node] + rho * deposit
            tau[node][prev] = tau[prev][node]
            prev = node

    # 2-opt local search — tüm iterasyonlar bittikten sonra
    if best_route:
        improved = True
        while improved:
            improved = False
            for i in range(len(best_route) - 1):
                for j in range(i + 2, len(best_route)):
                    new_route        = best_route[:]
                    new_route[i:j+1] = new_route[i:j+1][::-1]
                    new_fit          = calculate_fitness(new_route, dist_matrix, tasks, config, max_dist)
                    if new_fit < best_fit:
                        best_route = new_route
                        best_fit   = new_fit
                        improved   = True

    return best_route, history


def _avg_dist(dist_matrix, n):
    total = 0.0
    count = 0
    for i in range(1, n + 1):
        for j in range(1, n + 1):
            if i != j and dist_matrix[i][j] > 0:
                total += dist_matrix[i][j]
                count += 1
    return total / max(count, 1)