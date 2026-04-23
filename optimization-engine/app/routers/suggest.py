"""
City Suggestion System — Alt kategoriler, açık/kapalı filtresi, yarıçap
"""
import re, json, httpx, asyncio, random, time as _time
from fastapi  import APIRouter
from pydantic import BaseModel
from typing   import Optional

router = APIRouter()

OLLAMA_URL   = "http://localhost:11434/api/generate"
OLLAMA_MODEL = "mistral"
PLACES_URL   = "https://maps.googleapis.com/maps/api/place/textsearch/json"
DETAILS_URL  = "https://maps.googleapis.com/maps/api/place/details/json"

# ── Kategoriler ve alt kategoriler ────────────────────────────────────────────
CATEGORIES = {
    "yemek": {
        "label": "Yemek & Kafe",
        "icon" : "restaurant",
        "subcategories": {
            "restoran"  : {"label": "Restoran",      "type": "restaurant",   "query": "restoran"},
            "kafe"      : {"label": "Kafe",           "type": "cafe",         "query": "kafe kahve"},
            "fastfood"  : {"label": "Fast Food",      "type": "meal_takeaway","query": "fast food"},
            "pastane"   : {"label": "Pastane & Tatlı","type": "bakery",       "query": "pastane tatlı"},
            "cokcocuk"  : {"label": "Aile Dostu",     "type": "restaurant",   "query": "aile çocuk dostu restoran"},
        },
    },
    "gezinti": {
        "label": "Gezinti & Kültür",
        "icon" : "museum",
        "subcategories": {
            "muzeler"   : {"label": "Müzeler",        "type": "museum",             "query": "müze"},
            "tarihi"    : {"label": "Tarihi Yerler",  "type": "tourist_attraction", "query": "tarihi mekan anıt"},
            "sanat"     : {"label": "Sanat",          "type": "art_gallery",        "query": "sanat galerisi sergi"},
            "ibadet"    : {"label": "Dini Mekanlar",  "type": "mosque",             "query": "cami kilise dini mekan"},
        },
    },
    "eglence": {
        "label": "Eğlence & Aktivite",
        "icon" : "celebration",
        "subcategories": {
            "sinema"    : {"label": "Sinema",         "type": "movie_theater",  "query": "sinema"},
            "bowling"   : {"label": "Bowling & Oyun", "type": "bowling_alley",  "query": "bowling oyun salonu"},
            "cocuk"     : {"label": "Anne & Çocuk",   "type": "amusement_park", "query": "çocuk eğlence lunapark aile"},
            "konser"    : {"label": "Konser & Tiyatro","type": "night_club",    "query": "konser tiyatro sahne"},
        },
    },
    "alisveris": {
        "label": "Alışveriş",
        "icon" : "shopping_bag",
        "subcategories": {
            "avm"       : {"label": "AVM",            "type": "shopping_mall",    "query": "AVM alışveriş merkezi"},
            "carsi"     : {"label": "Çarşı & Pazar",  "type": "market",           "query": "çarşı pazar"},
            "butik"     : {"label": "Butik & Mağaza", "type": "clothing_store",   "query": "mağaza butik"},
        },
    },
    "doga": {
        "label": "Doğa & Park",
        "icon" : "park",
        "subcategories": {
            "park"      : {"label": "Park & Bahçe",   "type": "park",           "query": "park bahçe"},
            "doga"      : {"label": "Doğa & Orman",   "type": "natural_feature","query": "doğa orman göl"},
            "plaj"      : {"label": "Plaj & Sahil",   "type": "natural_feature","query": "plaj sahil"},
        },
    },
}

# Önbellek
_cache  : dict[str, dict]       = {}
_prefetch: dict[str, list[dict]] = {}
_TTL = 1800
_MAX = 20

def _cget(k):
    e = _cache.get(k)
    if e and (_time.time() - e["ts"]) < _TTL:
        return e["places"]
    _cache.pop(k, None)
    return None

def _cset(k, places):
    if len(_cache) >= _MAX:
        del _cache[min(_cache, key=lambda x: _cache[x]["ts"])]
    _cache[k] = {"places": places, "ts": _time.time()}


class UserPreferences(BaseModel):
    age_group      : str  = "yetiskin"
    budget         : str  = "orta"
    group_type     : str  = "yalniz"
    indoor_outdoor : str  = "ikisi"
    wheelchair     : bool = False
    child_friendly : bool = False


class SuggestRequest(BaseModel):
    city        : str
    district    : str             = ""
    category    : str             = "gezinti"
    subcategory : str             = ""        # boşsa tüm alt kategoriler
    api_key     : str
    max_results : int             = 8
    radius_km   : int             = 0         # 0 = sınırsız
    preferences : UserPreferences = UserPreferences()


class PlaceItem(BaseModel):
    name        : str
    address     : str
    rating      : float
    latitude    : float
    longitude   : float
    types       : list[str]
    place_id    : str
    price_level : int   = -1
    ai_reason   : str   = ""
    match_score : float = 0.0
    open_now    : Optional[bool] = None


class SuggestResponse(BaseModel):
    success        : bool
    places         : list[PlaceItem] = []
    summary        : str             = ""
    error          : str             = ""
    categories     : dict            = {}
    subcategories  : dict            = {}


async def _search(query: str, place_type: str, api_key: str,
                  max_results: int, location: str = "", radius_km: int = 0) -> list:
    params: dict = {
        "query"    : query,
        "key"      : api_key,
        "language" : "tr",
        "type"     : place_type,
        "opennow"  : "true",   # sadece açık olanlar
    }
    # Konum + yarıçap
    if radius_km > 0 and location:
        params["query"] = f"{query} {location}"
        params["radius"] = str(radius_km * 1000)

    async with httpx.AsyncClient(timeout=20) as c:
        resp = await c.get(PLACES_URL, params=params)
    data    = resp.json()
    results = data.get("results", [])
    q_short = query[:40]
    print(f"[Suggest] type={place_type} opennow=true {q_short!r} → {data.get('status')} {len(results)}")
    return results[:max_results * 3]


def _parse(results: list) -> list[dict]:
    places = []
    for r in results:
        loc = r.get("geometry", {}).get("location", {})
        pr  = r.get("price_level", -1)
        oh  = r.get("opening_hours", {})
        places.append({
            "name"       : r.get("name", ""),
            "address"    : r.get("formatted_address", ""),
            "rating"     : r.get("rating", 0.0),
            "latitude"   : loc.get("lat", 0.0),
            "longitude"  : loc.get("lng", 0.0),
            "types"      : r.get("types", []),
            "place_id"   : r.get("place_id", ""),
            "price_level": pr if isinstance(pr, int) else -1,
            "open_now"   : oh.get("open_now"),   # True/False/None
        })
    return places


async def _fetch(city, district, category, subcategory, prefs, api_key, max_results, radius_km) -> list[dict]:
    cat_info = CATEGORIES.get(category, CATEGORIES["gezinti"])
    location = f"{district} {city}".strip() if district else city

    # Alt kategori seçilmişse sadece onu çek, yoksa hepsini çek
    if subcategory and subcategory in cat_info["subcategories"]:
        subs = {subcategory: cat_info["subcategories"][subcategory]}
    else:
        subs = cat_info["subcategories"]

    all_results = []
    seen_ids    = set()

    for sub_key, sub_info in subs.items():
        query   = f"{sub_info['query']} {location}"
        results = await _search(query, sub_info["type"], api_key,
                                max_results, location, radius_km)
        for r in results:
            pid = r.get("place_id", "")
            if pid and pid not in seen_ids:
                seen_ids.add(pid)
                all_results.append(r)

    places = _parse(all_results)

    # Bütçe filtresi
    if prefs.budget == "ekonomik":
        f = [p for p in places if p["price_level"] in (-1, 0, 1, 2)]
        if f: places = f
    elif prefs.budget == "luks":
        f = [p for p in places if p["price_level"] in (-1, 3, 4)]
        if f: places = f

    # Adres tekilleştirme
    seen: dict = {}
    for p in places:
        key = p["address"].strip().lower() or p["place_id"]
        if key and (key not in seen or p["rating"] > seen[key]["rating"]):
            seen[key] = p

    result = list(seen.values())
    result.sort(key=lambda x: x["rating"], reverse=True)
    return result


def _score(place, prefs) -> float:
    score = place.get("rating", 3.0) / 5.0 * 0.7
    price = place.get("price_level", -1)
    if price != -1:
        if prefs.budget == "ekonomik" and price <= 1:   score += 0.20
        elif prefs.budget == "orta"   and price == 2:   score += 0.15
        elif prefs.budget == "luks"   and price >= 3:   score += 0.20
    return min(round(score, 2), 1.0)


async def _ollama(city, category, subcategory, prefs, places) -> tuple[list[str], str]:
    cat_label = CATEGORIES.get(category, {}).get("label", category)
    sub_label = ""
    if subcategory:
        subs = CATEGORIES.get(category, {}).get("subcategories", {})
        sub_label = subs.get(subcategory, {}).get("label", "")

    age = {"cocuk":"çocuk","genc":"genç","yetiskin":"yetişkin","yasli":"yaşlı"}.get(prefs.age_group,"")
    grp = {"yalniz":"yalnız","cift":"çift","aile":"aile","arkadas":"arkadaş grubu"}.get(prefs.group_type,"")
    label = f"{cat_label} › {sub_label}" if sub_label else cat_label
    lst   = "\n".join(f"{i+1}. {p['name']} ({p['rating']}★)" for i,p in enumerate(places))
    prompt = (
        f"{city} şehrinde {label} arayan {age} {grp} kullanıcı.\n"
        f"{lst}\n"
        f"Her mekan için 1 kısa Türkçe öneri cümlesi.\n"
        f'JSON: {{"summary":"özet","reasons":["1.","2.",...]}}'
    )
    try:
        async with httpx.AsyncClient(timeout=40) as c:
            r = await c.post(OLLAMA_URL, json={
                "model": OLLAMA_MODEL, "prompt": prompt, "stream": False,
                "options": {"num_predict": 400, "temperature": 0.3}
            })
        raw = r.json().get("response", "")
        m   = re.search(r'\{.*\}', raw, re.DOTALL)
        if m:
            d = json.loads(m.group())
            return d.get("reasons", []), d.get("summary", "")
    except Exception as e:
        print(f"[Ollama] {e}")
    return ["" for _ in places], ""


async def _do_prefetch(city, district, category, subcategory, prefs, api_key, max_results, radius_km, exclude_ids):
    key = f"{city}|{district}|{category}|{subcategory}"
    try:
        places = await _fetch(city, district, category, subcategory, prefs, api_key, max_results * 2, radius_km)
        fresh  = [p for p in places if p["place_id"] not in exclude_ids]
        _prefetch[key] = fresh[:max_results]
    except Exception as e:
        print(f"[Prefetch] {e}")


@router.post("/suggest", response_model=SuggestResponse)
async def suggest_places(req: SuggestRequest):
    city     = req.city.strip().title()
    district = req.district.strip().title() if req.district else ""

    if not city:
        return SuggestResponse(success=False, error="Şehir adı boş.")

    # Virgülle ayrılmış çoklu kategori desteği
    cats = [c.strip() for c in req.category.split(',') if c.strip()]
    if not cats:
        cats = ['gezinti']

    if len(cats) > 1:
        # Çoklu kategori: her birinden arama yap, birleştir
        all_places : list = []
        seen_ids   : set  = set()
        for cat in cats:
            cat_key = f"{city}|{district}|{cat}|{req.subcategory}"
            if cat_key in _prefetch:
                batch = _prefetch.pop(cat_key)
            else:
                cached = _cget(cat_key)
                if cached:
                    batch = cached
                else:
                    try:
                        batch = await _fetch(city, district, cat, req.subcategory,
                                             req.preferences, req.api_key,
                                             req.max_results, req.radius_km)
                        _cset(cat_key, batch)
                    except Exception:
                        batch = []
            for p in batch:
                if p['place_id'] not in seen_ids:
                    seen_ids.add(p['place_id'])
                    p['category_tag'] = cat
                    all_places.append(p)
        # Puana göre sırala
        all_places.sort(key=lambda x: x.get('rating', 0), reverse=True)
        places = all_places
        key    = f"{city}|{district}|{req.category}|{req.subcategory}"
    else:
        key = f"{city}|{district}|{cats[0]}|{req.subcategory}"
        if key in _prefetch:
            places = _prefetch.pop(key)
        else:
            cached = _cget(key)
            if cached:
                places = cached
            else:
                try:
                    places = await _fetch(city, district, cats[0], req.subcategory,
                                           req.preferences, req.api_key, req.max_results * 2, req.radius_km)
                    _cset(key, places)
                except Exception as e:
                    return SuggestResponse(success=False, error=f"Hata: {e}")

    if not places:
        return SuggestResponse(success=False, error=f"'{city}' için şu an açık mekan bulunamadı.")

    shown     = places[:req.max_results]
    shown_ids = [p["place_id"] for p in shown]
    reasons, summary = await _ollama(city, req.category, req.subcategory, req.preferences, shown)

    items = [
        PlaceItem(
            name        = p["name"],
            address     = p["address"],
            rating      = p["rating"],
            latitude    = p["latitude"],
            longitude   = p["longitude"],
            types       = p["types"],
            place_id    = p["place_id"],
            price_level = p.get("price_level", -1),
            open_now    = p.get("open_now"),
            ai_reason   = reasons[i] if i < len(reasons) else "",
            match_score = _score(p, req.preferences),
        )
        for i, p in enumerate(shown)
    ]
    items.sort(key=lambda x: x.match_score, reverse=True)

    asyncio.create_task(_do_prefetch(city, district, req.category, req.subcategory,
                                      req.preferences, req.api_key, req.max_results,
                                      req.radius_km, shown_ids))

    # Subcategory listesi
    subs = {
        k: v["label"]
        for k, v in CATEGORIES.get(req.category, {}).get("subcategories", {}).items()
    }

    return SuggestResponse(
        success       = True,
        places        = items,
        summary       = summary,
        categories    = {k: v["label"] for k, v in CATEGORIES.items()},
        subcategories = subs,
    )


class RefreshPlaceRequest(BaseModel):
    city        : str
    district    : str             = ""
    category    : str             = "gezinti"
    subcategory : str             = ""
    api_key     : str
    exclude_ids : list[str]       = []
    radius_km   : int             = 0
    preferences : UserPreferences = UserPreferences()


class RefreshPlaceResponse(BaseModel):
    success : bool
    place   : Optional[PlaceItem] = None
    error   : str                 = ""


@router.post("/suggest/refresh-place", response_model=RefreshPlaceResponse)
async def refresh_place(req: RefreshPlaceRequest):
    city     = req.city.strip().title()
    district = req.district.strip().title() if req.district else ""
    key      = f"{city}|{district}|{req.category}|{req.subcategory}"

    if key in _prefetch:
        candidates = [p for p in _prefetch[key] if p["place_id"] not in req.exclude_ids]
    else:
        try:
            all_places = await _fetch(city, district, req.category, req.subcategory,
                                       req.preferences, req.api_key, 20, req.radius_km)
            candidates = [p for p in all_places if p["place_id"] not in req.exclude_ids]
        except Exception as e:
            return RefreshPlaceResponse(success=False, error=str(e))

    if not candidates:
        return RefreshPlaceResponse(success=False, error="Yeni mekan bulunamadı.")

    pick       = random.choice(candidates[:5])
    reasons, _ = await _ollama(city, req.category, req.subcategory, req.preferences, [pick])

    return RefreshPlaceResponse(
        success=True,
        place=PlaceItem(
            name        = pick["name"],
            address     = pick["address"],
            rating      = pick["rating"],
            latitude    = pick["latitude"],
            longitude   = pick["longitude"],
            types       = pick["types"],
            place_id    = pick["place_id"],
            price_level = pick.get("price_level", -1),
            open_now    = pick.get("open_now"),
            ai_reason   = reasons[0] if reasons else "",
            match_score = _score(pick, req.preferences),
        ),
    )