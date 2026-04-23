"""
Genetic Algorithm — Memetic (GA + lokal arama)
Her bireye 2-opt + or-opt uygulanır → çok daha güçlü
"""
import random
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


def _or_opt(route):
    r = route[:]
    i = random.randint(0, len(r)-1)
    node = r.pop(i)
    j = random.randint(0, len(r))
    r.insert(j, node)
    return r


def _double_bridge(route):
    n = len(route)
    if n < 8:
        r = route[:]
        random.shuffle(r)
        return r
    a, b, c = sorted(random.sample(range(1, n), 3))
    return route[:a] + route[c:] + route[b:c] + route[a:b]


def _oxc(p1, p2):
    """Order crossover."""
    n = len(p1)
    a, b = sorted(random.sample(range(n), 2))
    child = [-1]*n
    child[a:b+1] = p1[a:b+1]
    remaining = [x for x in p2 if x not in child]
    idx = 0
    for i in range(n):
        if child[i] == -1:
            child[i] = remaining[idx]
            idx += 1
    return child


def _swap_mut(ind, rate):
    ind = ind[:]
    for i in range(len(ind)):
        if random.random() < rate:
            j = random.randint(0, len(ind)-1)
            ind[i], ind[j] = ind[j], ind[i]
    return ind


def _tournament(pop, dists, k=3):
    cands = random.sample(range(len(pop)), k)
    return pop[min(cands, key=lambda i: dists[i])][:]


def run_genetic_algorithm(
    tasks:       list[TaskModel],
    dist_matrix: list[list[float]],
    config:      OptimizationConfig,
) -> tuple[list[int], list[float]]:
    n        = len(tasks)
    pop_size = config.population_size  # 50
    gens     = config.generations      # 100
    mut_rate = config.mutation_rate
    max_dist = get_max_dist(dist_matrix)
    base     = list(range(1, n+1))

    # İlk popülasyon: NN+2opt + rastgele+2opt
    nn_r, nn_d = _two_opt(_nn(n, dist_matrix), dist_matrix)
    population = [nn_r[:]]
    distances  = [nn_d]

    # %30 double-bridge varyasyonları
    for _ in range(int(pop_size * 0.3)):
        r, d = _two_opt(_double_bridge(nn_r), dist_matrix)
        population.append(r)
        distances.append(d)

    # Geri kalan: rastgele+2opt
    while len(population) < pop_size:
        r = base[:]
        random.shuffle(r)
        r, d = _two_opt(r, dist_matrix)
        population.append(r)
        distances.append(d)

    best_idx  = distances.index(min(distances))
    best_route = population[best_idx][:]
    best_d    = distances[best_idx]
    history   = []
    stagnant  = 0

    for gen in range(gens):
        gen_best_d   = min(distances)
        gen_best_idx = distances.index(gen_best_d)

        if gen_best_d < best_d:
            best_d     = gen_best_d
            best_route = population[gen_best_idx][:]
            stagnant   = 0
        else:
            stagnant += 1

        fit = calculate_fitness(best_route, dist_matrix, tasks, config, max_dist)
        history.append(round(fit, 6))

        cur_mut  = min(mut_rate * (1 + stagnant * 0.05), 0.25)
        elite_n  = max(2, pop_size // 6)
        sorted_i = sorted(range(pop_size), key=lambda i: distances[i])

        new_pop   = [population[i][:] for i in sorted_i[:elite_n]]
        new_dists = [distances[i]     for i in sorted_i[:elite_n]]

        # Her 10 nesilde elite'e lokal arama
        if gen % 10 == 0:
            r, d = _two_opt(new_pop[0], dist_matrix)
            new_pop[0]   = r
            new_dists[0] = d
            if d < best_d:
                best_d, best_route = d, r[:]

        while len(new_pop) < pop_size:
            p1    = _tournament(population, distances)
            p2    = _tournament(population, distances)
            child = _oxc(p1, p2)
            if random.random() < 0.7:
                child = _swap_mut(child, cur_mut)
            else:
                child = _or_opt(child)
            # %20 ihtimalle lokal arama
            if random.random() < 0.20:
                child, d = _two_opt(child, dist_matrix)
            else:
                d = route_distance(child, dist_matrix)
            new_pop.append(child)
            new_dists.append(d)

        population = new_pop
        distances  = new_dists

    return best_route, history