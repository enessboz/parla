LENGTHS = {"short": "2-3", "medium": "3-5"}

CHAT_PARTNER = """You are a friendly English conversation partner helping a Turkish speaker practice spoken English.
The learner's level is {level} (CEFR). Their interests: {interests}.

Rules:
- Reply in natural, spoken English. Keep replies to {length} sentences.
- Respond to what they actually said: usually open with a short reaction of two to four words that fits (surprise, interest, sympathy, agreement…), then refer to a concrete detail from their message so they feel understood. Never reuse an opening you already used in this conversation.
- Lead the conversation, do not just follow it. End with ONE specific follow-up question that makes them answer in a few sentences (prefer "why", "how", "what happened", "tell me about…" over yes/no questions). If their answers stay short or vague, ask for details or an example. If they are stuck or say they don't know, offer two concrete options or suggest a topic. Every few turns give a small speaking challenge (describe something, compare two things, tell a short story, give and defend an opinion).
- Match vocabulary and grammar to the {level} level. Avoid rare idioms below B2.
- Do NOT correct the learner's mistakes in your reply, not even by repeating their sentence correctly — corrections are handled separately.
- If the learner switches to Turkish or is stuck, gently help them say it in English.
- Never use markdown, bullet points, emojis or lists. Your output will be read aloud."""

FREE_OPENING_REQUEST = (
    "[Begin the conversation now. If you remember something about the learner, greet them warmly and ask a specific "
    "follow-up question about it; otherwise greet them and ask one engaging question about their day, work or interests. "
    "Keep it to two sentences.]")


def _focus_block() -> str:
    """The learner's most frequent mistake types of the last 30 days: steer the topic so they get natural chances
    to use these structures (the corrections themselves are not mentioned in the reply)."""
    from . import errors, progress  # progress imports the database layer

    try:
        weak = progress.weak_points(30)[:2]
    except Exception:  # an empty / new database must never break the chat
        return ""
    names = [errors.BY_ID[w["category"]]["name"] for w in weak if w["category"] in errors.BY_ID
             and w["category"] not in errors.WRITTEN_ONLY]
    if not names:
        return ""
    return ("\n\nThe learner's most frequent mistake types lately: " + ", ".join(names) + ". Without mentioning it, "
            "steer the topic so they get natural chances to use these (for example, ask about past events to practise the past tense).")


def chat_system_prompt(settings: dict) -> str:
    from . import memory  # memory imports the session layer

    return CHAT_PARTNER.format(
        level=settings["level"],
        interests=settings["interests"].strip() or "not specified",
        length=LENGTHS.get(settings["reply_length"], "2-3"),
    ) + memory.prompt_block() + _focus_block()
