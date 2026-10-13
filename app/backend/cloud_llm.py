"""Cloud language models (OpenAI / Claude) next to the local Ollama ones.

A cloud model is addressed as "<provider>:<model>" ("openai:gpt-4o", "claude:claude-haiku-5-5") so it can travel
through the same `model` strings the rest of the app already passes around. ollama_client dispatches here.
API keys live in this computer's machine profile (config/machines/<name>.json, never synced or committed),
or in OPENAI_API_KEY / ANTHROPIC_API_KEY.
"""

import json
import os
import re
from typing import AsyncIterator

import httpx

from . import machine

PROVIDERS = {
    "openai": {"label": "OpenAI", "env": "OPENAI_API_KEY",
               "default": "gpt-4o", "fallback": ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]},
    "claude": {"label": "Claude", "env": "ANTHROPIC_API_KEY",
               "default": "claude-haiku-5-5",
               "fallback": ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"]},
}

_client = httpx.AsyncClient(timeout=httpx.Timeout(90.0, connect=10.0))


class CloudError(Exception):
    """User-facing (Turkish) message."""


def is_cloud(model: str) -> bool:
    return model.split(":", 1)[0] in PROVIDERS and ":" in model


def split(model: str) -> tuple[str, str]:
    provider, _, name = model.partition(":")
    return provider, name


def label(model: str) -> str:
    provider, name = split(model)
    return f"{PROVIDERS[provider]['label']} · {name}"


# ------------------------------------------------------------------ keys

def get_key(provider: str) -> str | None:
    key = (machine.load_profile().get("cloud_keys") or {}).get(provider) or os.environ.get(PROVIDERS[provider]["env"])
    return key.strip() if key else None


def set_key(provider: str, key: str) -> None:
    if provider not in PROVIDERS:
        raise CloudError("Bilinmeyen sağlayıcı.")
    keys = dict(machine.load_profile().get("cloud_keys") or {})
    if key.strip():
        keys[provider] = key.strip()
    else:
        keys.pop(provider, None)
    machine.update_profile({"cloud_keys": keys})


def configured() -> list[str]:
    return [p for p in PROVIDERS if get_key(p)]


def _need_key(provider: str) -> str:
    key = get_key(provider)
    if not key:
        raise CloudError(f"{PROVIDERS[provider]['label']} API anahtarı yok. Ayarlar → Dil modelleri → Bulut modeller'den ekleyin.")
    return key


# ------------------------------------------------------------------ errors

def _explain(provider: str, status: int, body: str) -> str:
    name = PROVIDERS[provider]["label"]
    if status == 401:
        return f"{name} API anahtarı geçersiz. Ayarlar'dan kontrol edin."
    if "insufficient_quota" in body or "credit balance" in body.lower() or "billing" in body.lower():
        return f"{name} hesabında kredi/kota yok. Faturalandırma sayfasından kredi ekleyin."
    if status == 429:
        return f"{name} istek sınırına takıldı, biraz sonra tekrar deneyin."
    if status == 404 or "model_not_found" in body or "not_found_error" in body:
        return f"{name} bu modeli bulamadı ya da erişiminiz yok. Ayarlar'dan başka bir model seçin."
    return f"{name} API hatası ({status}): {body[:240]}"


# ------------------------------------------------------------------ requests

def _max_tokens(options: dict | None, default: int = 400) -> int:
    n = int((options or {}).get("num_predict") or default)
    return n if n > 0 else default


def _openai_body(model: str, messages: list[dict], options: dict | None, stream: bool, json_mode: bool) -> dict:
    reasoning = model.startswith(("gpt-5", "o1", "o3", "o4"))
    tokens = _max_tokens(options)
    body = {
        "model": model, "stream": stream,
        "messages": [{"role": m["role"], "content": m["content"]} for m in messages],
        # Reasoning models spend part of the budget on hidden thinking: give them room.
        "max_completion_tokens": max(tokens * 8, 1500) if reasoning else tokens,
    }
    if reasoning:
        if model in ("gpt-5", "gpt-5-mini", "gpt-5-nano"):
            body["reasoning_effort"] = "minimal"
    else:
        body["temperature"] = float((options or {}).get("temperature", 0.7))
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    return body


def _claude_parts(messages: list[dict]) -> tuple[str, list[dict]]:
    system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
    turns: list[dict] = []
    for m in messages:
        if m["role"] == "system":
            continue
        if not turns and m["role"] != "user":
            continue  # must start with a user turn
        if turns and turns[-1]["role"] == m["role"]:
            turns[-1]["content"] += "\n" + m["content"]
        else:
            turns.append({"role": m["role"], "content": m["content"]})
    return system, turns


def _claude_body(model: str, messages: list[dict], options: dict | None, stream: bool, schema_hint: str | None) -> dict:
    system, turns = _claude_parts(messages)
    if schema_hint:
        system += ("\n\nReturn ONLY a valid JSON object (no markdown, no commentary) that matches this JSON Schema:\n"
                   + schema_hint)
    body = {"model": model, "max_tokens": max(_max_tokens(options), 600) if schema_hint else _max_tokens(options),
            "messages": turns, "stream": stream, "temperature": float((options or {}).get("temperature", 0.7))}
    if system:
        body["system"] = system
    return body


def _request(provider: str, body: dict) -> tuple[str, dict]:
    key = _need_key(provider)
    if provider == "openai":
        return "https://api.openai.com/v1/chat/completions", {"Authorization": f"Bearer {key}"}
    return "https://api.anthropic.com/v1/messages", {"x-api-key": key, "anthropic-version": "2023-06-01"}


# ------------------------------------------------------------------ public API

async def stream(model: str, messages: list[dict], options: dict | None = None) -> AsyncIterator[str]:
    provider, name = split(model)
    body = (_openai_body(name, messages, options, True, False) if provider == "openai"
            else _claude_body(name, messages, options, True, None))
    url, headers = _request(provider, body)
    try:
        async with _client.stream("POST", url, json=body, headers=headers) as resp:
            if resp.status_code != 200:
                raise CloudError(_explain(provider, resp.status_code, (await resp.aread()).decode(errors="replace")))
            async for line in resp.aiter_lines():
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    ev = json.loads(payload)
                except ValueError:
                    continue
                if provider == "openai":
                    choices = ev.get("choices") or []
                    text = ((choices[0].get("delta") or {}).get("content") or "") if choices else ""
                else:
                    text = (ev.get("delta") or {}).get("text", "") if ev.get("type") == "content_block_delta" else ""
                    if ev.get("type") == "message_stop":
                        break
                if text:
                    yield text
    except httpx.HTTPError as e:
        raise CloudError(f"{PROVIDERS[provider]['label']} API'ye ulaşılamadı (internet bağlantısı?): {e.__class__.__name__}") from e


async def _once(model: str, messages: list[dict], options: dict | None, schema: dict | None) -> str:
    provider, name = split(model)
    if provider == "openai":
        msgs = [dict(m) for m in messages]
        if schema is not None:
            hint = ("\n\nReturn ONLY a valid JSON object (no markdown) that matches this JSON Schema:\n"
                    + json.dumps(schema, ensure_ascii=False))
            for m in msgs:
                if m["role"] == "system":
                    m["content"] += hint
                    break
            else:
                msgs.insert(0, {"role": "system", "content": "Output JSON only." + hint})
        body = _openai_body(name, msgs, options, False, schema is not None)
        if schema is not None:
            body["max_completion_tokens"] = max(body["max_completion_tokens"], 1200)
    else:
        body = _claude_body(name, messages, options, False, json.dumps(schema, ensure_ascii=False) if schema else None)
    url, headers = _request(provider, body)
    try:
        resp = await _client.post(url, json=body, headers=headers)
    except httpx.HTTPError as e:
        raise CloudError(f"{PROVIDERS[provider]['label']} API'ye ulaşılamadı (internet bağlantısı?): {e.__class__.__name__}") from e
    if resp.status_code != 200:
        raise CloudError(_explain(provider, resp.status_code, resp.text))
    data = resp.json()
    if provider == "openai":
        return ((data.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")


async def complete(model: str, messages: list[dict], options: dict | None = None) -> str:
    return (await _once(model, messages, options, None)).strip()


async def chat_json(model: str, messages: list[dict], schema: dict, options: dict | None = None) -> dict:
    text = await _once(model, messages, options, schema)
    a, b = text.find("{"), text.rfind("}")
    if a != -1 and b > a:
        text = text[a:b + 1]
    try:
        return json.loads(text)
    except ValueError as e:
        raise CloudError("Model geçerli JSON döndürmedi.") from e


# ------------------------------------------------------------------ model lists

_BANNED = ("audio", "realtime", "transcribe", "tts", "image", "search", "instruct", "embedding", "moderation",
           "vision", "codex", "whisper", "dall", "computer", "chat-latest", "deep-research")


async def list_models(provider: str) -> list[str]:
    """The models this account can use (live), or a sensible fallback list when offline / no key."""
    fallback = list(PROVIDERS[provider]["fallback"])
    key = get_key(provider)
    if not key:
        return fallback
    try:
        if provider == "openai":
            resp = await _client.get("https://api.openai.com/v1/models", headers={"Authorization": f"Bearer {key}"}, timeout=15)
            if resp.status_code != 200:
                return fallback
            ids = [m["id"] for m in resp.json().get("data", [])]
            ids = [i for i in ids if i.startswith(("gpt-", "o1", "o3", "o4"))
                   and not any(b in i for b in _BANNED)
                   and not re.search(r"-\d{4}-\d{2}-\d{2}$|-\d{4}$", i)]
            return sorted(set(ids)) or fallback
        resp = await _client.get("https://api.anthropic.com/v1/models?limit=100",
                                 headers={"x-api-key": key, "anthropic-version": "2023-06-01"}, timeout=15)
        if resp.status_code != 200:
            return fallback
        return [m["id"] for m in resp.json().get("data", [])] or fallback
    except (httpx.HTTPError, ValueError, KeyError):
        return fallback


def recommended(provider: str, models: list[str]) -> list[str]:
    """The strongest few first; gpt-4o always stays on the list."""
    if provider == "claude":
        order = ["haiku", "sonnet", "opus", "fable"]
        return sorted(models, key=lambda m: next((i for i, k in enumerate(order) if k in m), 9))[:5]

    def rank(i: str) -> tuple:
        group = 0 if i.startswith("gpt-5") else 1 if i.startswith("gpt-4.1") else 2 if i.startswith(("o3", "o4")) else 9
        return (group, "mini" in i, [-ord(c) for c in i])
    top = sorted((m for m in models if rank(m)[0] < 9 and "nano" not in m), key=rank)[:4]
    for must in ("gpt-4o", "gpt-4o-mini"):
        if must in models and must not in top:
            top.append(must)
    return top or ["gpt-4o", "gpt-4o-mini"]
