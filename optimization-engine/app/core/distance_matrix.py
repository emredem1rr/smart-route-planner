"""
Distance & Duration Matrix Builder
- Haversine: hızlı, kuş uçuşu
- OSRM Table API: tek istekle n×n matris, gerçek yol mesafesi
"""
import asyncio
import httpx
import math
from .models import TaskModel, StartLocation

# Public OSRM — ücretsiz ama rate limit var
OSRM_TABLE_URL = "http://router.project-osrm.org/table/v1/driving"
OSRM_ROUTE_URL = "http://router.project-osrm.org/route/v1/driving"


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