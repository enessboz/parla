# Minimal OpenAI + Anthropic stand-in for tests: uvicorn fake_cloud:app --port 11600
import json, asyncio
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse
app = FastAPI()

def reply_for(messages):
    last = [m for m in messages if m["role"] == "user"][-1]["content"]
    return f"Nice, you said: {last[:60]}. Why is that?"

@app.get("/v1/models")
def models(request: Request):
    if request.headers.get("x-api-key"):
        return {"data": [{"id": "claude-haiku-5-5"}, {"id": "claude-sonnet-5-5"}]}
    return {"data": [{"id": i} for i in ("gpt-4o", "gpt-4o-mini", "gpt-5", "gpt-5-mini", "gpt-4.1", "text-embedding-3-small", "gpt-4o-audio-preview")]}

@app.post("/v1/chat/completions")
async def openai(req: Request):
    if req.headers.get("authorization") != "Bearer sk-test":
        return JSONResponse({"error": {"message": "bad key"}}, 401)
    body = await req.json()
    if body.get("response_format"):
        content = json.dumps({"corrected": "I went to school.", "errors": []})
        return {"choices": [{"message": {"content": content}}]}
    text = reply_for(body["messages"])
    if not body.get("stream"):
        return {"choices": [{"message": {"content": text}}]}
    async def gen():
        for w in text.split(" "):
            await asyncio.sleep(0.01)
            yield "data: " + json.dumps({"choices": [{"delta": {"content": w + " "}}]}) + "\n\n"
        yield "data: [DONE]\n\n"
    return StreamingResponse(gen(), media_type="text/event-stream")

@app.post("/v1/messages")
async def claude(req: Request):
    if req.headers.get("x-api-key") != "sk-ant-test":
        return JSONResponse({"error": {"type": "authentication_error"}}, 401)
    body = await req.json()
    assert body["messages"][0]["role"] == "user"
    if "JSON" in body.get("system", ""):
        return {"content": [{"type": "text", "text": json.dumps({"corrected": "ok", "errors": []})}]}
    text = reply_for(body["messages"])
    if not body.get("stream"):
        return {"content": [{"type": "text", "text": text}]}
    async def gen():
        for w in text.split(" "):
            await asyncio.sleep(0.01)
            yield "data: " + json.dumps({"type": "content_block_delta", "delta": {"type": "text_delta", "text": w + " "}}) + "\n\n"
        yield "data: " + json.dumps({"type": "message_stop"}) + "\n\n"
    return StreamingResponse(gen(), media_type="text/event-stream")
