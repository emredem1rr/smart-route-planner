"""
User Personalization — Gemini ile görev geçmişinden kullanıcı profili çıkarma.
"""
import re, json, time
from fastapi  import APIRouter
from pydantic import BaseModel
from typing   import Optional
from ..ai_provider import generate as ai_generate

router = APIRouter()

# ── In-memory profil cache (30 dk TTL) ────────────────────────────────────────
_profile_cache: dict[str, dict] = {}
_PROFILE_TTL = 1800  # saniye


def _cache_get(user_id: str) -> Optional[dict]:
    entry = _profile_cache.get(user_id)
    if entry and (time.time() - entry['ts']) < _PROFILE_TTL:
        return entry['profile']
    _profile_cache.pop(user_id, None)
    return None


def _cache_set(user_id: str, profile: dict) -> None:
    _profile_cache[user_id] = {'profile': profile, 'ts': time.time()}


# ── Modeller ───────────────────────────────────────────────────────────────────
class PersonalizeRequest(BaseModel):
    user_id      : str
    task_history : list[dict] = []   # [{name, address, lat, lon, task_date, category, ...}]


class PersonalizeResponse(BaseModel):
    success  : bool
    profile  : Optional[dict] = None
    error    : str            = ""


# ── Varsayılan category_boost ─────────────────────────────────────────────────
_DEFAULT_BOOST: dict[str, float] = {
    'yemek'    : 0.5, 'gezinti'   : 0.5, 'eglence': 0.5,
    'alisveris': 0.5, 'doga'      : 0.5,
}


def _build_fallback_profile(task_history: list[dict]) -> dict:
    """Gemini yoksa istatistiksel fallback profil."""
    cat_counts: dict[str, int] = {}
    hours: list[int]           = []

    for t in task_history:
        cat = str(t.get('category', '')).lower()
        if cat:
            cat_counts[cat] = cat_counts.get(cat, 0) + 1
        date_str = str(t.get('task_date', ''))
        if 'T' in date_str:
            try:
                h = int(date_str.split('T')[1][:2])
                hours.append(h)
            except Exception:
                pass

    boost = dict(_DEFAULT_BOOST)
    if cat_counts:
        total = sum(cat_counts.values())
        for cat, cnt in cat_counts.items():
            if cat in boost:
                boost[cat] = min(round(0.3 + (cnt / total) * 0.7, 2), 1.0)

    top_cats = sorted(cat_counts, key=lambda c: cat_counts[c], reverse=True)[:3]
    avg_hour = round(sum(hours) / len(hours)) if hours else 10
    period   = 'sabah' if avg_hour < 12 else ('öğleden sonra' if avg_hour < 17 else 'akşam')

    return {
        'preferred_categories' : top_cats,
        'typical_hour'         : avg_hour,
        'activity_period'      : period,
        'activity_description' : (
            f"Kullanıcı genellikle {period} görev yapıyor, "
            f"en çok {', '.join(top_cats) or 'çeşitli'} kategorilerini tercih ediyor."
        ),
        'category_boost'       : boost,
    }


async def _build_ai_profile(user_id: str, task_history: list[dict]) -> dict:
    """Gemini ile kişiselleştirilmiş profil oluştur."""
    sample = task_history[-30:]   # son 30 görev yeterli
    task_lines = '\n'.join(
        f"- {t.get('name','?')} ({t.get('category','?')}) — {t.get('task_date','?')}"
        for t in sample
    )
    category_list = 'yemek, gezinti, eglence, alisveris, doga'
    boost_template = ', '.join(f'"{c}": 0.5' for c in ['yemek', 'gezinti', 'eglence', 'alisveris', 'doga'])

    prompt = (
        f"Kullanıcı görev geçmişi (son {len(sample)} görev):\n"
        f"{task_lines}\n\n"
        f"Bu geçmişi analiz et:\n"
        f"1. Kullanıcının sık gittiği kategoriler ({category_list})\n"
        f"2. Tipik çalışma saati (0-23)\n"
        f"3. Aktivite dönemi (sabah/öğleden sonra/akşam)\n"
        f"4. 1-2 cümle Türkçe kullanıcı özeti\n"
        f"5. Her kategori için 0.0-1.0 arası tercih skoru\n\n"
        f'JSON: {{"preferred_categories":["cat1"],"typical_hour":10,'
        f'"activity_period":"sabah","activity_description":"özet",'
        f'"category_boost":{{{boost_template}}}}}'
    )

    try:
        raw    = await ai_generate(prompt, max_tokens=400)
        match  = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            data = json.loads(match.group())
            # Boost değerlerini 0-1 arasında zorla
            raw_boost = data.get('category_boost', {})
            boost = {
                cat: min(max(float(raw_boost.get(cat, 0.5)), 0.0), 1.0)
                for cat in ['yemek', 'gezinti', 'eglence', 'alisveris', 'doga']
            }
            return {
                'preferred_categories' : data.get('preferred_categories', []),
                'typical_hour'         : int(data.get('typical_hour', 10)),
                'activity_period'      : str(data.get('activity_period', 'sabah')),
                'activity_description' : str(data.get('activity_description', '')),
                'category_boost'       : boost,
            }
    except Exception as e:
        print(f"[Personalize AI] {e}")

    return _build_fallback_profile(task_history)


# ── Endpoint ───────────────────────────────────────────────────────────────────
@router.post('/personalize', response_model=PersonalizeResponse)
async def personalize(req: PersonalizeRequest):
    if not req.user_id:
        return PersonalizeResponse(success=False, error='user_id boş.')
    if not req.task_history:
        return PersonalizeResponse(
            success = True,
            profile = {
                'preferred_categories' : [],
                'typical_hour'         : 10,
                'activity_period'      : 'sabah',
                'activity_description' : 'Henüz görev geçmişi yok.',
                'category_boost'       : dict(_DEFAULT_BOOST),
            },
        )

    cached = _cache_get(req.user_id)
    if cached:
        return PersonalizeResponse(success=True, profile=cached)

    profile = await _build_ai_profile(req.user_id, req.task_history)
    _cache_set(req.user_id, profile)
    return PersonalizeResponse(success=True, profile=profile)
