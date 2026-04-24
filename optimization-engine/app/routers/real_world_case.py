"""
Gerçek Hayat Senaryoları — Samsun/Amasya koordinatları ile TSP benchmark.
"""
import math, time, re, json, asyncio
from fastapi  import APIRouter, Query
from pydantic import BaseModel
from typing   import Optional
from ..core.models import TaskModel, OptimizationConfig
from ..algorithms.genetic             import run_genetic_algorithm
from ..algorithms.simulated_annealing import run_simulated_annealing
from ..algorithms.ant_colony          import run_ant_colony
from ..algorithms.tabu_search         import run_tabu_search
from ..algorithms.lin_kernighan       import run_lin_kernighan
from ..ai_provider                    import generate as ai_generate

router = APIRouter()

# ── Haversine ─────────────────────────────────────────────────────────────────
def _hav(lat1, lon1, lat2, lon2) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


def _dist_matrix(stops: list[dict]) -> list[list[float]]:
    n   = len(stops)
    mat = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i != j:
                mat[i][j] = _hav(
                    stops[i]['lat'], stops[i]['lon'],
                    stops[j]['lat'], stops[j]['lon'],
                )
    return mat


# ── Gerçek Hayat Senaryoları ───────────────────────────────────────────────────
SCENARIOS = {
    'kurye': {
        'label': 'Kurye — 10 Durak',
        'city' : 'Samsun',
        'stops': [
            {'name': 'Kargo Merkezi (Başlangıç)', 'lat': 41.2867, 'lon': 36.3304},
            {'name': 'Atakum Mah. Teslimat',       'lat': 41.3276, 'lon': 36.2921},
            {'name': 'İlkadım PTT',                'lat': 41.2939, 'lon': 36.3325},
            {'name': 'Canik Belediyesi',            'lat': 41.2655, 'lon': 36.3895},
            {'name': 'Ondokuz Mayıs Üniversitesi', 'lat': 41.3452, 'lon': 36.2557},
            {'name': 'Tekkeköy Sanayi',             'lat': 41.2201, 'lon': 36.4623},
            {'name': 'Batıpark AVM',                'lat': 41.2993, 'lon': 36.2810},
            {'name': 'Samsun Adliyesi',             'lat': 41.2862, 'lon': 36.3428},
            {'name': 'Piazza AVM',                  'lat': 41.3015, 'lon': 36.3192},
            {'name': 'Bafra Yolu Teslimat',         'lat': 41.3801, 'lon': 36.1945},
        ],
    },
    'satis': {
        'label': 'Satış Temsilcisi — 7 Durak',
        'city' : 'Amasya',
        'stops': [
            {'name': 'Merkez Ofis',             'lat': 40.6499, 'lon': 35.8353},
            {'name': 'Suluova Bayi',            'lat': 40.7777, 'lon': 35.6510},
            {'name': 'Merzifon Distribütör',    'lat': 40.8749, 'lon': 35.4680},
            {'name': 'Taşova Müşteri',          'lat': 40.3918, 'lon': 36.3263},
            {'name': 'Gümüşhacıköy Eczane',    'lat': 40.8688, 'lon': 35.2141},
            {'name': 'Hamamözü Bayi',           'lat': 40.6226, 'lon': 35.5804},
            {'name': 'Amasya Üniversitesi',     'lat': 40.6620, 'lon': 35.8291},
        ],
    },
    'saglik': {
        'label': 'Sağlık Ziyaretçisi — 5 Durak',
        'city' : 'Amasya',
        'stops': [
            {'name': 'Amasya Devlet Hastanesi', 'lat': 40.6491, 'lon': 35.8458},
            {'name': 'Suluova Sağlık Merkezi',  'lat': 40.7750, 'lon': 35.6480},
            {'name': 'Merzifon Yaşlı Bakım',    'lat': 40.8702, 'lon': 35.4621},
            {'name': 'Taşova Klinik',           'lat': 40.3881, 'lon': 36.3240},
            {'name': 'Gümüşhacıköy Poliklinik', 'lat': 40.8645, 'lon': 35.2105},
        ],
    },
}


# ── Algoritma Runner ───────────────────────────────────────────────────────────
class BenchResult(BaseModel):
    algorithm         : str
    total_distance_km : float
    execution_time_ms : float
    route_order       : list[str]
    gap_vs_best       : float = 0.0   # % fark — en iyi algoritmaya göre
    gap_vs_manual     : float = 0.0   # % fark — manuel sıraya göre


def _run_scenario(stops: list[dict], config: OptimizationConfig) -> list[BenchResult]:
    tasks = [
        TaskModel(
            id=i + 1, name=s['name'], address='',
            latitude=s['lat'], longitude=s['lon'],
            duration=15, priority=3,
        )
        for i, s in enumerate(stops[1:])  # 0. durak başlangıç, görevler 1..n
    ]
    start_stop = stops[0]
    dist_mat   = _dist_matrix(stops)

    results = []
    for name, fn in [
        ('genetic',             run_genetic_algorithm),
        ('simulated_annealing', run_simulated_annealing),
        ('ant_colony',          run_ant_colony),
        ('tabu_search',         run_tabu_search),
        ('lin_kernighan',       run_lin_kernighan),
    ]:
        t0          = time.perf_counter()
        route, _    = fn(tasks, dist_mat, config)
        elapsed     = (time.perf_counter() - t0) * 1000
        ordered     = [stops[r]['name'] for r in route if r > 0]
        total_dist  = (
            dist_mat[0][route[0]]
            + sum(dist_mat[route[i]][route[i + 1]] for i in range(len(route) - 1))
        )
        results.append(BenchResult(
            algorithm         = name,
            total_distance_km = round(total_dist, 2),
            execution_time_ms = round(elapsed, 1),
            route_order       = [start_stop['name']] + ordered,
        ))
    return results


ALGO_LABELS = {
    'genetic':             'Genetik Algoritma',
    'simulated_annealing': 'Simüle Tavlama',
    'ant_colony':          'Karınca Kolonisi',
    'tabu_search':         'Tabu Arama',
    'lin_kernighan':       'Lin-Kernighan',
}


async def _interpret(scenario_label: str, results: list[BenchResult]) -> str:
    best  = min(results, key=lambda r: r.total_distance_km)
    worst = max(results, key=lambda r: r.total_distance_km)
    gap   = round((worst.total_distance_km - best.total_distance_km)
                  / best.total_distance_km * 100, 1) if best.total_distance_km > 0 else 0
    lines = '\n'.join(
        f"- {ALGO_LABELS.get(r.algorithm, r.algorithm)}: "
        f"{r.total_distance_km} km, {r.execution_time_ms:.1f} ms"
        for r in results
    )
    prompt = (
        f"Senaryo: {scenario_label}\n"
        f"Algoritma sonuçları:\n{lines}\n\n"
        f"En iyi: {ALGO_LABELS.get(best.algorithm, best.algorithm)} ({best.total_distance_km} km). "
        f"En kötü ile aradaki fark: %{gap}.\n\n"
        f"Bu sonuçları Türkçe, 2-3 cümle, akademik ama anlaşılır biçimde yorumla. "
        f"Sadece yorum metnini yaz."
    )
    try:
        raw = await asyncio.wait_for(ai_generate(prompt, max_tokens=250), timeout=10.0)
        if raw and not raw.startswith('{'):
            return raw.strip()
    except Exception as e:
        print(f"[RealWorld AI] {e}")

    best_label = ALGO_LABELS.get(best.algorithm, best.algorithm)
    return (
        f"{scenario_label} senaryosunda {best_label} en kısa rotayı buldu "
        f"({best.total_distance_km} km). "
        f"En iyi ve en kötü algoritma arasında %{gap} mesafe farkı gözlemlendi."
    )


# ── Response Modeli ────────────────────────────────────────────────────────────
class ScenarioResult(BaseModel):
    scenario_key              : str   = ""
    label                     : str
    city                      : str
    n_stops                   : int
    results                   : list[BenchResult]
    winner                    : str
    winner_distance_km        : float
    manual_distance_km        : float = 0.0
    improvement_vs_manual_pct : float = 0.0  # ((manuel - best) / manuel * 100)
    km_saved                  : float = 0.0
    ai_interpretation         : str
    execution_time_ms         : float


class RealWorldResponse(BaseModel):
    success   : bool
    scenarios : list[ScenarioResult] = []
    error     : str                  = ""


# ── Endpoint ───────────────────────────────────────────────────────────────────
@router.get('/benchmark/real-world', response_model=RealWorldResponse)
async def real_world_benchmark(scenario: Optional[str] = Query(default=None)):
    config = OptimizationConfig(
        heuristic       = 'euclidean',
        population_size = 80,
        generations     = 150,
        mutation_rate   = 0.02,
        use_real_roads  = False,
        use_traffic     = False,
    )

    keys_to_run = (
        [scenario] if scenario and scenario in SCENARIOS
        else list(SCENARIOS.keys())
    )

    scenario_results: list[ScenarioResult] = []

    for key in keys_to_run:
        sc      = SCENARIOS[key]
        stops   = sc['stops']
        t0      = time.perf_counter()
        results = await asyncio.to_thread(_run_scenario, stops, config)
        elapsed = (time.perf_counter() - t0) * 1000

        best       = min(results, key=lambda r: r.total_distance_km)
        best_dist  = best.total_distance_km

        # Manuel mesafe: orijinal durak sırasıyla
        dist_mat      = _dist_matrix(stops)
        manual_dist   = round(
            dist_mat[0][1] + sum(dist_mat[i][i + 1] for i in range(1, len(stops) - 1)),
            2,
        )
        improv_pct = round((manual_dist - best_dist) / manual_dist * 100, 1) if manual_dist > 0 else 0.0
        km_saved   = round(manual_dist - best_dist, 2)

        # Gap hesapla: her algoritmanın en iyiye ve manüele göre farkı
        for r in results:
            r.gap_vs_best   = round((r.total_distance_km - best_dist) / best_dist * 100, 1) if best_dist > 0 else 0.0
            r.gap_vs_manual = round((manual_dist - r.total_distance_km) / manual_dist * 100, 1) if manual_dist > 0 else 0.0

        interp = await _interpret(sc['label'], results)

        scenario_results.append(ScenarioResult(
            scenario_key              = key,
            label                     = sc['label'],
            city                      = sc['city'],
            n_stops                   = len(stops),
            results                   = results,
            winner                    = best.algorithm,
            winner_distance_km        = best_dist,
            manual_distance_km        = manual_dist,
            improvement_vs_manual_pct = improv_pct,
            km_saved                  = km_saved,
            ai_interpretation         = interp,
            execution_time_ms         = round(elapsed, 1),
        ))

    return RealWorldResponse(success=True, scenarios=scenario_results)
