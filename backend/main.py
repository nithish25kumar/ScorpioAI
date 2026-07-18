"""
FastAPI chatbot backend.

Endpoints:
- GET  /health          liveness check
- POST /chat            streams the assistant's reply (Server-Sent Events)
- POST /chat/sync        same as /chat but returns the full reply in one JSON response (used by tests / simple clients)
- POST /ingest/text      add raw text to the RAG knowledge base
- POST /ingest/file      add a .txt or .pdf file to the RAG knowledge base
- GET  /ingest/status    whether any documents have been ingested yet

Works with any OpenAI-compatible LLM API (Gemini, Groq, OpenRouter, OpenAI).
Change LLM_BASE_URL / LLM_MODEL in your .env file to switch providers.
"""

import os
import json
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from openai import OpenAI
from dotenv import load_dotenv

import rag

load_dotenv()

API_KEY = os.environ.get("LLM_API_KEY")
BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.groq.com/openai/v1")
MODEL = os.environ.get("LLM_MODEL", "llama-3.3-70b-versatile")

if not API_KEY:
    raise RuntimeError("LLM_API_KEY is not set. Copy .env.example to .env and fill it in.")

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

app = FastAPI(title="Flutter Chatbot Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

SYSTEM_PROMPT = (
    "You are a helpful, friendly assistant inside a mobile app. "
    "Keep answers clear and reasonably concise."
)

RAG_SYSTEM_PROMPT = (
    "You are a helpful, friendly assistant inside a mobile app. "
    "Use the following context to answer the user's question if it's relevant. "
    "If the context doesn't contain the answer, use your general knowledge instead, "
    "and don't mention that you were given context.\n\nContext:\n{context}"
)


class Message(BaseModel):
    role: str  # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    message: str
    history: list[Message] = []


class ChatResponse(BaseModel):
    reply: str


class IngestTextRequest(BaseModel):
    text: str
    source: str = "manual"


def build_messages(req: ChatRequest) -> list[dict]:
    """Build the message list for the LLM, injecting retrieved context if available."""
    if rag.has_documents():
        chunks = rag.retrieve(req.message, top_k=3)
        if chunks:
            context = "\n\n---\n\n".join(chunks)
            system = RAG_SYSTEM_PROMPT.format(context=context)
        else:
            system = SYSTEM_PROMPT
    else:
        system = SYSTEM_PROMPT

    messages = [{"role": "system", "content": system}]
    messages += [{"role": m.role, "content": m.content} for m in req.history]
    messages.append({"role": "user", "content": req.message})
    return messages


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat")
def chat_stream(req: ChatRequest):
    """Streams the reply as Server-Sent Events: lines of `data: {"delta": "..."}`."""
    messages = build_messages(req)

    def event_generator():
        try:
            stream = client.chat.completions.create(
                model=MODEL,
                messages=messages,
                stream=True,
            )
            for chunk in stream:
                delta = chunk.choices[0].delta.content
                if delta:
                    yield f"data: {json.dumps({'delta': delta})}\n\n"
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.post("/chat/sync", response_model=ChatResponse)
def chat_sync(req: ChatRequest):
    """Non-streaming variant: waits for the full reply and returns it as JSON."""
    messages = build_messages(req)
    try:
        response = client.chat.completions.create(model=MODEL, messages=messages)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM request failed: {e}")
    return ChatResponse(reply=response.choices[0].message.content)


@app.post("/ingest/text")
def ingest_text(req: IngestTextRequest):
    count = rag.ingest_text(req.text, source=req.source)
    return {"chunks_added": count}


@app.post("/ingest/file")
async def ingest_file(file: UploadFile = File(...)):
    contents = await file.read()

    if file.filename.lower().endswith(".pdf"):
        try:
            from pypdf import PdfReader
            import io

            reader = PdfReader(io.BytesIO(contents))
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Could not read PDF: {e}")
    else:
        text = contents.decode("utf-8", errors="ignore")

    count = rag.ingest_text(text, source=file.filename)
    return {"filename": file.filename, "chunks_added": count}


@app.get("/ingest/status")
def ingest_status():
    return {"has_documents": rag.has_documents()}
