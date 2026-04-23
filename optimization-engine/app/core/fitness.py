import math
from .models import TaskModel, OptimizationConfig


def haversine_km(lat1, lon1, lat2, lon2):
    R    = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a    = (math.sin(dphi / 2) ** 2 +
            math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def calculate_route_stats(route, dist_matrix, tasks):
    if not route:
        return {'total_distance': 0.0, 'total_travel_time': 0.0}

    # 0 = başlangıç noktası, route[i] = görev index'i (1-based)
    # Başlangıç → 1. görev → 2. görev → ... şeklinde sıralı hesap
    total_distance = dist_matrix[0][route[0]]
    for i in range(len(route) - 1):
        total_distance += dist_matrix[route[i]][route[i + 1]]

    total_travel_time  = (total_distance / 50.0) * 60.0
    total_service_time = sum(tasks[r - 1].duration for r in route)

    return {
        'total_distance':    round(total_distance,    4),
        'total_travel_time': round(total_travel_time + total_service_time, 2),
    }


def get_max_dist(dist_matrix: list[list[float]]) -> float:
    max_d = 1.0
    for row in dist_matrix:
        for v in row:
            if v > max_d:
                max_d = v
    return max_d


def route_distance(route, dist_matrix) -> float:
    """Ham mesafe — normalize etmez. SA ve Tabu için kullanılır."""
    if not route:
        return float('inf')
    d = dist_matrix[0][route[0]]
    for i in range(len(route) - 1):
        d += dist_matrix[route[i]][route[i + 1]]
    return d


def calculate_fitness(route, dist_matrix, tasks, config, max_dist: float = None):
    if not route:
        return float('inf')

    total_distance   = 0.0
    priority_penalty = 0.0
    time_penalty     = 0.0

    # Mesafe: başlangıç → route[0] → route[1] → ... sıralı
    total_distance += dist_matrix[0][route[0]]
    for i in range(len(route) - 1):
        total_distance += dist_matrix[route[i]][route[i + 1]]

    # Öncelik cezası
    for pos, task_idx in enumerate(route):
        task = tasks[task_idx - 1]
        priority_penalty += pos * (6 - task.priority)

    # Zaman penceresi cezası — önceki görevden sıralı hesap
    current_time = 0.0
    for i, task_idx in enumerate(route):
        task = tasks[task_idx - 1]
        # i==0: başlangıçtan ilk göreve, sonraki: önceki görevden
        prev = 0 if i == 0 else route[i - 1]
        travel        = dist_matrix[prev][task_idx] / 50.0 * 60.0
        current_time += travel

        if task.earliest_start > 0 and current_time < task.earliest_start:
            current_time = float(task.earliest_start)

        if task.latest_finish < 1440:
            finish_time = current_time + task.duration
            if finish_time > task.latest_finish:
                time_penalty += (finish_time - task.latest_finish) * 2.0

        current_time += task.duration

    if max_dist is None:
        max_dist = get_max_dist(dist_matrix)

    return round(
        total_distance   / max(max_dist, 1.0)
        + priority_penalty * 0.3
        + time_penalty     * 0.5,
        6,
    )