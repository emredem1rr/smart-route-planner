"""
City Suggestion System — AI filters, natural-language search, Gemini/Ollama AI
"""
import re, json, httpx, asyncio, random, time as _time
from fastapi  import APIRouter
from pydantic import BaseModel
from typing   import Optional
from ..ai_provider import generate as ai_generate

router = APIRouter()

PLACES_URL   = "https://maps.googleapis.com/maps/api/place/textsearch/json"
DETAILS_URL  = "https://maps.googleapis.com/maps/api/place/details/json"

# ── Kategoriler ────────────────────────────────────────────────────────────────
CATEGORIES = {
    "yemek": {
        "label": "Yemek & Kafe",
        "icon" : "restaurant",
        "subcategories": {
            "restoran"  : {"label": "Restoran",       "type": "restaurant",    "query": "restoran"},
            "kafe"      : {"label": "Kafe",            "type": "cafe",          "query": "kafe kahve"},
            "fastfood"  : {"label": "Fast Food",       "type": "meal_takeaway", "query": "fast food"},
            "pastane"   : {"label": "Pastane & Tatlı", "type": "bakery",        "query": "pastane tatlı"},
            "cokcocuk"  : {"label": "Aile Dostu",      "type": "restaurant",    "query": "aile çocuk dostu restoran"},
        },
    },
    "gezinti": {
        "label": "Gezinti & Kültür",
        "icon" : "museum",
        "subcategories": {
            "muzeler"   : {"label": "Müzeler",         "type": "museum",             "query": "müze"},
            "tarihi"    : {"label": "Tarihi Yerler",   "type": "tourist_attraction", "query": "tarihi mekan anıt"},
            "sanat"     : {"label": "Sanat",           "type": "art_gallery",        "query": "sanat galerisi sergi"},
            "ibadet"    : {"label": "Dini Mekanlar",   "type": "mosque",             "query": "cami kilise dini mekan"},
        },
    },
    "eglence": {
        "label": "Eğlence & Aktivite",
        "icon" : "celebration",
        "subcategories": {
            "sinema"    : {"label": "Sinema",          "type": "movie_theater",  "query": "sinema"},
            "bowling"   : {"label": "Bowling & Oyun",  "type": "bowling_alley",  "query": "bowling oyun salonu"},
            "cocuk"     : {"label": "Anne & Çocuk",    "type": "amusement_park", "query": "çocuk eğlence lunapark aile"},
            "konser"    : {"label": "Konser & Tiyatro", "type": "night_club",    "query": "konser tiyatro sahne"},
        },
    },
    "alisveris": {
        "label": "Alışveriş",
        "icon" : "shopping_bag",
        "subcategories": {
            "avm"       : {"label": "AVM",             "type": "shopping_mall",  "query": "AVM alışveriş merkezi"},
            "carsi"     : {"label": "Çarşı & Pazar",   "type": "market",         "query": "çarşı pazar"},
            "butik"     : {"label": "Butik & Mağaza",  "type": "clothing_store", "query": "mağaza butik"},
        },
    },
    "doga": {
        "label": "Doğa & Park",
        "icon" : "park",
        "subcategories": {
            "park"      : {"label": "Park & Bahçe",    "type": "park",            "query": "park bahçe"},
            "doga"      : {"label": "Doğa & Orman",    "type": "natural_feature", "query": "doğa orman göl"},
            "plaj"      : {"label": "Plaj & Sahil",    "type": "natural_feature", "query": "plaj sahil"},
        },
    },
}

# ── AI Filtre Anahtar Kelimeleri ───────────────────────────────────────────────
FILTER_KEYWORDS: dict[str, list[str]] = {
    "çocuğa uygun"    : ["çocuk", "bebek", "çocuklar", "oyun alanı", "kids", "çocuklu", "bebek arabası"],
    "aile dostu"      : ["aile", "family", "çocuklu aile", "aile ortamı", "çocuklar"],
    "gençler için"    : ["genç", "öğrenci", "youth", "modern", "canlı", "enerjik", "hareketli"],
    "sessiz ortam"    : ["sessiz", "sakin", "quiet", "huzurlu", "romantik", "rahat", "dinlendirici"],
    "vejetaryen"      : ["vejetaryen", "vegan", "vejeteryan", "bitkisel", "salata", "vegetarian"],
    "engelli erişimi" : ["engelli", "tekerlekli sandalye", "rampa", "asansör", "erişilebilir", "wheelchair"],
    "evcil hayvan dostu": ["köpek", "kedi", "hayvan", "pet", "evcil hayvan", "animal friendly"],
    "wifi var"        : ["wifi", "wi-fi", "internet", "kablosuz", "bağlantı", "hotspot"],
    "açık alan"       : ["bahçe", "teras", "balkon", "açık alan", "outdoor", "dışarıda", "dış mekan"],
}

# ── Cache ──────────────────────────────────────────────────────────────────────
_cache   : dict[str, dict]       = {}
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


# ── Pydantic Modeller ──────────────────────────────────────────────────────────
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
    subcategory : str             = ""
    api_key     : str
    max_results : int             = 8
    radius_km   : int             = 0
    preferences : UserPreferences = UserPreferences()
    filters     : list[str]       = []   # AI filtre listesi


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
    success       : bool
    places        : list[PlaceItem] = []
    summary       : str             = ""
    error         : str             = ""
    categories    : dict            = {}
    subcategories : dict            = {}


# ── Google Places Çağrıları ────────────────────────────────────────────────────
async def _search(query: str, place_type: str, api_key: str,
                  max_results: int, location: str = "", radius_km: int = 0) -> list:
    params: dict = {
        "query"   : query,
        "key"     : api_key,
        "language": "tr",
        "type"    : place_type,
    }
    if radius_km > 0 and location:
        params["query"]  = f"{query} {location}"
        params["radius"] = str(radius_km * 1000)

    async with httpx.AsyncClient(timeout=20) as c:
        resp = await c.get(PLACES_URL, params=params)
    data    = resp.json()
    results = data.get("results", [])
    print(f"[Suggest] {place_type} {query[:35]!r} → {data.get('status')} {len(results)}")
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
            "open_now"   : oh.get("open_now"),
        })
    return places


async def _fetch(city, district, category, subcategory, prefs, api_key,
                 max_results, radius_km) -> list[dict]:
    cat_info = CATEGORIES.get(category, CATEGORIES["gezinti"])
    location = f"{district} {city}".strip() if district else city

    subs = (
        {subcategory: cat_info["subcategories"][subcategory]}
        if subcategory and subcategory in cat_info["subcategories"]
        else cat_info["subcategories"]
    )

    all_results: list = []
    seen_ids: set     = set()

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

    if prefs.budget == "ekonomik":
        f = [p for p in places if p["price_level"] in (-1, 0, 1, 2)]
        if f: places = f
    elif prefs.budget == "luks":
        f = [p for p in places if p["price_level"] in (-1, 3, 4)]
        if f: places = f

    seen: dict = {}
    for p in places:
        key = p["address"].strip().lower() or p["place_id"]
        if key and (key not in seen or p["rating"] > seen[key]["rating"]):
            seen[key] = p

    result = list(seen.values())
    result.sort(key=lambda x: x["rating"], reverse=True)
    return result


# ── AI: Öneri metni ────────────────────────────────────────────────────────────
async def _ai_suggest(city, category, subcategory, prefs, places) -> tuple[list[str], str]:
    cat_label = CATEGORIES.get(category, {}).get("label", category)
    sub_label = ""
    if subcategory:
        subs      = CATEGORIES.get(category, {}).get("subcategories", {})
        sub_label = subs.get(subcategory, {}).get("label", "")

    age = {"cocuk": "çocuk", "genc": "genç", "yetiskin": "yetişkin", "yasli": "yaşlı"}.get(prefs.age_group, "")
    grp = {"yalniz": "yalnız", "cift": "çift", "aile": "aile", "arkadas": "arkadaş grubu"}.get(prefs.group_type, "")
    label = f"{cat_label} › {sub_label}" if sub_label else cat_label
    lst   = "\n".join(f"{i+1}. {p['name']} ({p['rating']}★)" for i, p in enumerate(places))

    prompt = (
        f"{city} şehrinde {label} arayan {age} {grp} kullanıcı.\n"
        f"{lst}\n"
        f"Her mekan için 1 kısa Türkçe öneri cümlesi yaz.\n"
        f'JSON: {{"summary":"özet","reasons":["1.","2.",...]}}'
    )
    try:
        raw = await ai_generate(prompt, max_tokens=400)
        m   = re.search(r'\{.*\}', raw, re.DOTALL)
        if m:
            d = json.loads(m.group())
            return d.get("reasons", []), d.get("summary", "")
    except Exception as e:
        print(f"[AI Suggest] {e}")
    return ["" for _ in places], ""


# ── AI: Filtre Analizi ─────────────────────────────────────────────────────────
async def _get_reviews(place_id: str, api_key: str) -> list[str]:
    """Google Places Details'den en fazla 5 review çek."""
    try:
        params = {"place_id": place_id, "fields": "reviews",
                  "key": api_key, "language": "tr"}
        async with httpx.AsyncClient(timeout=10) as c:
            r = await c.get(DETAILS_URL, params=params)
        reviews = r.json().get("result", {}).get("reviews", [])
        return [rv.get("text", "") for rv in reviews[:5] if rv.get("text")]
    except Exception:
        return []


async def _analyze_filters(place_name: str, reviews: list[str],
                            filters: list[str]) -> dict[str, float]:
    """Review'ları analiz ederek her filtre için 0-1 uygunluk skoru döndür."""
    if not filters:
        return {}

    review_text = " ".join(reviews).lower()

    # Anahtar kelime tabanlı temel skor
    scores: dict[str, float] = {}
    for f in filters:
        kws  = FILTER_KEYWORDS.get(f, [])
        if not review_text.strip():
            scores[f] = 0.5  # review yok → nötr
            continue
        if kws:
            hits      = sum(1 for kw in kws if kw in review_text)
            scores[f] = min(hits / max(len(kws) * 0.4, 1), 1.0)
        else:
            scores[f] = 0.5

    # AI ile zenginleştir (review varsa)
    if review_text.strip():
        filter_list = ", ".join(f'"{f}"' for f in filters)
        empty_scores = ", ".join(f'"{f}": 0.0' for f in filters)
        prompt = (
            f"Mekan: {place_name}\n"
            f"Yorumlar (özet): {review_text[:600]}\n\n"
            f"Aşağıdaki filtreler için 0.0-1.0 arası uygunluk skoru ver:\n"
            f"{filter_list}\n"
            f'Sadece JSON: {{"scores": {{{empty_scores}}}}}'
        )
        try:
            raw = await ai_generate(prompt, max_tokens=200)
            m   = re.search(r'\{.*\}', raw, re.DOTALL)
            if m:
                ai_scores = json.loads(m.group()).get("scores", {})
                for f in filters:
                    if f in ai_scores:
                        scores[f] = (scores.get(f, 0.5) + float(ai_scores[f])) / 2
        except Exception as e:
            print(f"[Filter AI] {e}")

    return scores


def _score(place: dict, prefs: UserPreferences,
           filter_scores: dict[str, float] | None = None) -> float:
    base = place.get("rating", 3.0) / 5.0 * 0.5
    price = place.get("price_level", -1)
    if price != -1:
        if prefs.budget == "ekonomik" and price <= 1:   base += 0.15
        elif prefs.budget == "orta"   and price == 2:   base += 0.10
        elif prefs.budget == "luks"   and price >= 3:   base += 0.15

    if filter_scores:
        avg_filter = sum(filter_scores.values()) / len(filter_scores)
        base += avg_filter * 0.35
    else:
        base += 0.15

    return min(round(base, 2), 1.0)


# ── Prefetch ───────────────────────────────────────────────────────────────────
async def _do_prefetch(city, district, category, subcategory, prefs,
                       api_key, max_results, radius_km, exclude_ids):
    key = f"{city}|{district}|{category}|{subcategory}"
    try:
        places = await _fetch(city, district, category, subcategory,
                              prefs, api_key, max_results * 2, radius_km)
        fresh  = [p for p in places if p["place_id"] not in exclude_ids]
        _prefetch[key] = fresh[:max_results]
    except Exception as e:
        print(f"[Prefetch] {e}")


# ── /suggest ───────────────────────────────────────────────────────────────────
@router.post("/suggest", response_model=SuggestResponse)
async def suggest_places(req: SuggestRequest):
    city     = req.city.strip().title()
    district = req.district.strip().title() if req.district else ""

    if not city:
        return SuggestResponse(success=False, error="Şehir adı boş.")

    cats = [c.strip() for c in req.category.split(',') if c.strip()]
    if not cats:
        cats = ['gezinti']

    if len(cats) > 1:
        all_places: list = []
        seen_ids: set    = set()
        for cat in cats:
            cat_key = f"{city}|{district}|{cat}|{req.subcategory}"
            batch   = (_prefetch.pop(cat_key, None) or _cget(cat_key))
            if batch is None:
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
        all_places.sort(key=lambda x: x.get('rating', 0), reverse=True)
        places = all_places
        key    = f"{city}|{district}|{req.category}|{req.subcategory}"
    else:
        key    = f"{city}|{district}|{cats[0]}|{req.subcategory}"
        places = _prefetch.pop(key, None) or _cget(key)
        if places is None:
            try:
                places = await _fetch(city, district, cats[0], req.subcategory,
                                       req.preferences, req.api_key,
                                       req.max_results * 2, req.radius_km)
                _cset(key, places)
            except Exception as e:
                return SuggestResponse(success=False, error=f"Hata: {e}")

    if not places:
        return SuggestResponse(success=False, error=f"'{city}' için mekan bulunamadı.")

    shown     = places[:req.max_results]
    shown_ids = [p["place_id"] for p in shown]

    # AI öneri metinleri
    reasons, summary = await _ai_suggest(city, req.category, req.subcategory,
                                          req.preferences, shown)

    # AI filtre analizi (filtre seçildiyse)
    filter_scores_map: dict[str, dict[str, float]] = {}
    if req.filters:
        review_tasks = [_get_reviews(p["place_id"], req.api_key) for p in shown]
        all_reviews  = await asyncio.gather(*review_tasks, return_exceptions=True)
        analyze_tasks = [
            _analyze_filters(p["name"],
                             reviews if isinstance(reviews, list) else [],
                             req.filters)
            for p, reviews in zip(shown, all_reviews)
        ]
        filter_results = await asyncio.gather(*analyze_tasks, return_exceptions=True)
        for p, fs in zip(shown, filter_results):
            filter_scores_map[p["place_id"]] = fs if isinstance(fs, dict) else {}

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
            match_score = _score(p, req.preferences,
                                 filter_scores_map.get(p["place_id"])),
        )
        for i, p in enumerate(shown)
    ]
    items.sort(key=lambda x: x.match_score, reverse=True)

    asyncio.create_task(_do_prefetch(
        city, district, req.category, req.subcategory,
        req.preferences, req.api_key, req.max_results, req.radius_km, shown_ids
    ))

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


# ── /suggest/refresh-place ────────────────────────────────────────────────────
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
    reasons, _ = await _ai_suggest(city, req.category, req.subcategory, req.preferences, [pick])

    return RefreshPlaceResponse(
        success = True,
        place   = PlaceItem(
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


# ── /suggest/natural-language ─────────────────────────────────────────────────
class NaturalLanguageRequest(BaseModel):
    query       : str
    api_key     : str
    max_results : int             = 8
    preferences : UserPreferences = UserPreferences()


class _NLParsed(BaseModel):
    city       : str
    district   : str       = ""
    category   : str       = "gezinti"
    subcategory: str       = ""
    filters    : list[str] = []


async def _parse_nl(query: str) -> _NLParsed:
    cats_str    = ", ".join(CATEGORIES.keys())
    filters_str = ", ".join(FILTER_KEYWORDS.keys())
    prompt = (
        f"Kullanıcı sorgusu: '{query}'\n"
        f"Mevcut kategoriler: {cats_str}\n"
        f"Mevcut filtreler: {filters_str}\n\n"
        f"Şehir, ilçe, kategori, alt kategori ve uygun filtreleri Türkçe sorguda çıkar.\n"
        f"Kategori sadece mevcut listeden seçilmeli.\n"
        f'JSON örnek: {{"city":"İstanbul","district":"Kadıköy","category":"yemek","subcategory":"kafe","filters":["aile dostu","sessiz ortam"]}}'
    )
    try:
        raw = await ai_generate(prompt, max_tokens=250)
        m   = re.search(r'\{.*\}', raw, re.DOTALL)
        if m:
            d = json.loads(m.group())
            cat = d.get("category", "gezinti")
            if cat not in CATEGORIES:
                cat = "gezinti"
            return _NLParsed(
                city        = str(d.get("city", "")).strip(),
                district    = str(d.get("district", "")).strip(),
                category    = cat,
                subcategory = str(d.get("subcategory", "")).strip(),
                filters     = [f for f in d.get("filters", []) if f in FILTER_KEYWORDS],
            )
    except Exception as e:
        print(f"[NL Parse] {e}")

    # Basit fallback: son kelime → şehir
    words = query.strip().split()
    return _NLParsed(city=words[-1] if words else "")


@router.post("/suggest/natural-language", response_model=SuggestResponse)
async def suggest_natural_language(req: NaturalLanguageRequest):
    parsed = await _parse_nl(req.query)
    if not parsed.city:
        return SuggestResponse(success=False,
                               error="Sorgudan şehir adı çıkarılamadı. Lütfen şehri açıkça belirtin.")
    suggest_req = SuggestRequest(
        city        = parsed.city,
        district    = parsed.district,
        category    = parsed.category,
        subcategory = parsed.subcategory,
        api_key     = req.api_key,
        max_results = req.max_results,
        preferences = req.preferences,
        filters     = parsed.filters,
    )
    return await suggest_places(suggest_req)
