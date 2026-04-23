"""
AI Provider — Gemini Flash (primary) → Ollama/Mistral (fallback) → template fallback.
All AI calls in the application should go through the `generate` function.
"""
import os
import httpx
from typing import Optional

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models"
    "/gemini-1.5-flash:generateContent"
)
_OLLAMA_BASE  = os.getenv("OLLAMA_URL", "http://localhost:11434")
OLLAMA_URL    = _OLLAMA_BASE.rstrip("/") + "/api/generate"
OLLAMA_MODEL  = "mistral"


async def generate(prompt: str, max_tokens: int = 500) -> str:
    """Gemini Flash → Ollama/Mistral → template fallback."""
    if GEMINI_API_KEY:
        result = await _gemini(prompt, max_tokens)
        if result is not None:
            return result
    result = await _ollama(prompt, max_tokens)
    if result is not None:
        return result
    return '{"summary": "AI analizi şu an kullanılamıyor.", "reasons": []}'


async def _gemini(prompt: str, max_tokens: int) -> Optional[str]:
    try:
        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.post(
                f"{GEMINI_URL}?key={GEMINI_API_KEY}",
                json={
                    "contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {
                        "maxOutputTokens": max_tokens,
                        "temperature": 0.3,
                    },
                },
            )
        if r.status_code == 429:
            print("[Gemini] Rate limit (429) — Ollama fallback")
            return None
        if r.status_code != 200:
            print(f"[Gemini] HTTP {r.status_code}: {r.text[:200]}")
            return None
        data = r.json()
        return data["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        print(f"[Gemini] {e}")
        return None


async def _ollama(prompt: str, max_tokens: int) -> Optional[str]:
    try:
        async with httpx.AsyncClient(timeout=40) as c:
            r = await c.post(
                OLLAMA_URL,
                json={
                    "model": OLLAMA_MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"num_predict": max_tokens, "temperature": 0.3},
                },
            )
        if r.status_code != 200:
            print(f"[Ollama] HTTP {r.status_code}")
            return None
        return r.json().get("response", "")
    except Exception as e:
        print(f"[Ollama] {e}")
        return None
