"""Long-term memory of the conversation partner: short facts about the learner (name, job, hobbies, plans…),
kept across sessions and shown to the LLM, so conversations can follow up on earlier ones.

Notes are refreshed in the background every few messages by the same LLM that chats; a running refresh is
cancelled when a new chat turn starts, so it never delays a reply.
"""

import asyncio
import logging

from . import llm_models, ollama_client, sessions
from .db import get_conn, now_iso
from .ollama_client import OllamaError

log = logging.getLogger("memory")

MAX_NOTES = 20
REFRESH_EVERY = 3  # user messages

SCHEMA = {
    "type": "object",
    "properties": {"notes": {"type": "array", "items": {"type": "string"}}},
    "required": ["notes"],
}

PROMPT = """You maintain a short long-term memory about an English learner (a Turkish speaker). It is used to personalise future conversations.

Current notes:
{notes}

Latest conversation excerpt:
{excerpt}

Return the updated list of notes. Keep only durable, useful facts: name, job or studies, family, pets, hobbies, places, goals, plans and events they mentioned (with the timeframe if known), opinions, and topics worth following up on later. One short English sentence per note, in the third person (for example "Works as a nurse in Ankara." or "Is travelling to Izmir next weekend."). Merge duplicates, fix outdated notes, keep at most {max_notes}. If nothing new was said, return the current notes unchanged."""

_task: asyncio.Task | None = None


def notes() -> list[dict]:
    with get_conn() as conn:
        rows = conn.execute("SELECT id, text FROM memory_notes ORDER BY id").fetchall()
    return [{"id": r["id"], "text": r["text"]} for r in rows]


def set_all(texts: list[str]) -> None:
    clean = []
    for t in texts:
        t = " ".join(str(t).split())[:200]
        if t and t.lower() not in {c.lower() for c in clean}:
            clean.append(t)
    with get_conn() as conn:
        conn.execute("DELETE FROM memory_notes")
        conn.executemany("INSERT INTO memory_notes (text, created_at) VALUES (?, ?)",
                         [(t, now_iso()) for t in clean[:MAX_NOTES]])


def delete(note_id: int) -> None:
    with get_conn() as conn:
        conn.execute("DELETE FROM memory_notes WHERE id = ?", (note_id,))


def clear() -> None:
    with get_conn() as conn:
        conn.execute("DELETE FROM memory_notes")


def prompt_block() -> str:
    items = notes()
    if not items:
        return ""
    return ("\n\nWhat you remember about the learner from earlier conversations (use it naturally, never list it; "
            "now and then ask a follow-up about something here):\n" + "\n".join(f"- {n['text']}" for n in items))


def cancel() -> None:
    """A chat turn starts: drop a running refresh (the next one catches up)."""
    global _task
    if _task and not _task.done():
        _task.cancel()
    _task = None


def schedule(session_id: int) -> None:
    """After a reply in a free conversation: refresh the notes every REFRESH_EVERY user messages."""
    global _task
    recent = sessions.recent_messages(session_id, 40)
    user_count = sum(1 for m in recent if m["role"] == "user")
    if user_count == 0 or user_count % REFRESH_EVERY:
        return
    if _task and not _task.done():
        return
    _task = asyncio.create_task(_refresh(recent[-10:]))


async def _refresh(messages: list[dict]) -> None:
    excerpt = "\n".join(("Learner: " if m["role"] == "user" else "Partner: ") + m["content"][:300] for m in messages)
    current = "\n".join(f"- {n['text']}" for n in notes()) or "(none yet)"
    prompt = PROMPT.format(notes=current, excerpt=excerpt, max_notes=MAX_NOTES)
    try:
        await llm_models.manager.wait_idle()
        result = await ollama_client.chat_json(
            llm_models.current(),
            [{"role": "user", "content": prompt}], SCHEMA, options={"num_predict": 500, "temperature": 0.1})
    except asyncio.CancelledError:
        raise
    except OllamaError as e:
        log.info("memory refresh skipped: %s", e)
        return
    new = [n for n in result.get("notes", []) if isinstance(n, str)]
    if new:
        set_all(new)
