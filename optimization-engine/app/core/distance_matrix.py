"""
Distance & Duration Matrix Builder
- Haversine: hızlı, kuş uçuşu
- OSRM Table API: tek istekle n×n matris, gerçek yol mesafesi
- Google Distance Matrix API: trafik verisiyle gerçek zamanlı süre
"""
import asyncio
import httpx
import math
import os
from .models import TaskModel, StartLocation

# Public OSRM — ücretsiz ama rate limit var
OSRM_TABLE_URL = "http://router.project-osrm.org/table/v1/driving"
OSRM_ROUTE_URL = "http://router.project-osrm.org/route/v1/driving"

# Google Distance Matrix API
GOOGLE_DM_URL  = "https://maps.googleapis.com/maps/api/distancematrix/json"
GOOGLE_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R    = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a    = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def build_distance_matrix(
    start: StartLocation,
    tasks: list[TaskModel],
) -> list[list[float]]:
    """Senkron haversine — fallback."""
    locations = [(start.latitude, start.longitude)] + [
        (t.latitude, t.longitude) for t in tasks
    ]
    n      = len(locations)
    matrix = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i != j:
                matrix[i][j] = haversine_km(
                    locations[i][0], locations[i][1],
                    locations[j][0], locations[j][1],
                )
    return matrix


async def build_distance_matrix_async(
    start: StartLocation,
    tasks: list[TaskModel],
) -> tuple[list[list[float]], list[list[float]]]:
    """
    OSRM Table API ile tek istekte n×n dist + duration matrisi.
    Başarısız olursa haversine fallback döner.
    """
    locations = [(start.latitude, start.longitude)] + [
        (t.latitude, t.longitude) for t in tasks
    ]
    n = len(locations)

    # OSRM koordinat stringi: lon,lat;lon,lat;...
    coords = ";".join(f"{lon},{lat}" for lat, lon in locations)
    url    = f"{OSRM_TABLE_URL}/{coords}?annotations=distance,duration"

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url)
            data = resp.json()

        if data.get("code") != "Ok":
            raise ValueError(f"OSRM error: {data.get('code')}")

        raw_dist = data["distances"]   # metre cinsinden
        raw_dur  = data["durations"]   # saniye cinsinden

        dist_matrix     = [[0.0] * n for _ in range(n)]
        duration_matrix = [[0.0] * n for _ in range(n)]

        for i in range(n):
            for j in range(n):
                dist_matrix[i][j]     = (raw_dist[i][j] or 0) / 1000.0   # km
                duration_matrix[i][j] = (raw_dur[i][j]  or 0) / 60.0     # dakika

        return dist_matrix, duration_matrix

    except Exception as e:
        print(f"[OSRM Table] failed: {e} — haversine fallback")
        dist = build_distance_matrix(start, tasks)
        # Haversine için süre: 40 km/h ortalama şehir içi hız
        dur  = [[dist[i][j] / 40.0 * 60.0 for j in range(n)] for i in range(n)]
        return dist, dur


async def build_traffic_matrix_async(
    start: StartLocation,
    tasks: list[TaskModel],
) -> tuple[list[list[float]], list[list[float]]]:
    """
    Google Distance Matrix API — departure_time=now ile trafik verisi.
    Başarısız olursa OSRM'e fallback yapar.
    """
    if not GOOGLE_API_KEY:
        print("[Google DM] API key yok — OSRM fallback")
        return await build_distance_matrix_async(start, tasks)

    locations = [(start.latitude, start.longitude)] + [
        (t.latitude, t.longitude) for t in tasks
    ]
    n = len(locations)

    # Google DM API max 10 origins × 10 destinations destekler
    # Büyük problemler için parça parça istek at
    MAX_CHUNK = 10
    dist_matrix     = [[0.0] * n for _ in range(n)]
    duration_matrix = [[0.0] * n for _ in range(n)]

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            for i_start in range(0, n, MAX_CHUNK):
                origins = "|".join(
                    f"{lat},{lon}"
                    for lat, lon in locations[i_start: i_start + MAX_CHUNK]
                )
                for j_start in range(0, n, MAX_CHUNK):
                    destinations = "|".join(
                        f"{lat},{lon}"
                        for lat, lon in locations[j_start: j_start + MAX_CHUNK]
                    )
                    params = {
                        "origins"        : origins,
                        "destinations"   : destinations,
                        "key"            : GOOGLE_API_KEY,
                        "departure_time" : "now",
                        "traffic_model"  : "best_guess",
                        "mode"           : "driving",
                    }
                    resp = await client.get(GOOGLE_DM_URL, params=params)
                    data = resp.json()

                    if data.get("status") != "OK":
                        raise ValueError(f"Google DM error: {data.get('status')}")

                    for ri, row in enumerate(data["rows"]):
                        gi = i_start + ri
                        for ci, elem in enumerate(row["elements"]):
                            gj = j_start + ci
                            if elem.get("status") == "OK":
                                dist_matrix[gi][gj] = elem["distance"]["value"] / 1000.0
                                dur_key = "duration_in_traffic" if "duration_in_traffic" in elem else "duration"
                                duration_matrix[gi][gj] = elem[dur_key]["value"] / 60.0

        print(f"[Google DM] Trafik matrisi: {n}×{n}")
        return dist_matrix, duration_matrix

    except Exception as e:
        print(f"[Google DM] failed: {e} — OSRM fallback")
        return await build_distance_matrix_async(start, tasks)


async def get_route_geometry(
    locations: list[tuple[float, float]],
) -> list[tuple[float, float]] | None:
    """
    OSRM Route API — harita üzerinde gerçek yol çizgisi için koordinatlar.
    Returns list of (lat, lon) veya None.
    """
    if len(locations) < 2:
        return None

    coords = ";".join(f"{lon},{lat}" for lat, lon in locations)
    url    = f"{OSRM_ROUTE_URL}/{coords}?overview=full&geometries=geojson"

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url)
            data = resp.json()

        if data.get("code") != "Ok":
            return None

        # GeoJSON koordinatları [lon, lat] formatında geliyor
        coords_raw = data["routes"][0]["geometry"]["coordinates"]
        return [(lat, lon) for lon, lat in coords_raw]

    except Exception as e:
        print(f"[OSRM Route] failed: {e}")
        return None