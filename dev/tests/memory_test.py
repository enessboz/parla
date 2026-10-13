"""AI-led opening + long-term memory against a test server (fake cloud model as default).
Run: curl -X PUT .../api/cloud/key (openai sk-test) + PUT /api/llm/default openai:gpt-4o first (see start of file)."""
import asyncio, json, sys, urllib.request
import websockets

PORT = sys.argv[1] if len(sys.argv) > 1 else "8100"
BASE = f"http://127.0.0.1:{PORT}"

def call(path, method="GET", body=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req))

async def turn(ws, payload, cid):
    await ws.send(json.dumps({**payload, "client_id": cid, "speak": False}))
    sid, text = None, ""
    while True:
        ev = json.loads(await ws.recv())
        if ev.get("client_id") != cid:
            continue
        if ev["type"] == "meta":
            sid = ev["session_id"]
        elif ev["type"] == "delta":
            text += ev["text"]
        elif ev["type"] == "done":
            return sid, ev["text"]
        elif ev["type"] == "error":
            raise SystemExit("error: " + ev["message"])

async def main():
    call("/api/cloud/key", "PUT", {"provider": "openai", "key": "sk-test"})
    call("/api/llm/default", "PUT", {"model": "openai:gpt-4o"})
    call("/api/memory", "DELETE")
    async with websockets.connect(f"ws://127.0.0.1:{PORT}/ws/voice", max_size=None) as ws:
        sid, opener = await turn(ws, {"type": "start_chat"}, "o1")
        print("opening:", opener[:80], "session", sid)
        assert sid and opener
        for i, t in enumerate(["I am nurse in Ankara", "I like football very much", "Yesterday I go to the stadium"]):
            sid, reply = await turn(ws, {"type": "text", "text": t, "session_id": sid}, f"c{i}")
            print("reply:", reply[:60])
        await asyncio.sleep(1.5)  # background memory refresh
    notes = call("/api/memory")["notes"]
    print("memory:", [n["text"] for n in notes])
    assert notes, "memory was not written"
    call("/api/memory", "POST", {"text": "Has a dog called Max."})
    n = call("/api/memory")["notes"]
    call(f"/api/memory/{n[0]['id']}", "DELETE")
    assert len(call("/api/memory")["notes"]) == len(n) - 1
    print("OK")

asyncio.run(main())
