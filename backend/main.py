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
from fastapi import FastAPI, HTTPException, UploadFile, File, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from openai import OpenAI
from dotenv import load_dotenv

import rag
import auth
import db

load_dotenv()

API_KEY = os.environ.get("LLM_API_KEY")
BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.groq.com/openai/v1")
MODEL = os.environ.get("LLM_MODEL", "llama-3.3-70b-versatile")

if not API_KEY:
    raise RuntimeError("LLM_API_KEY is not set. Copy .env.example to .env and fill it in.")

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

db.init_db()

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


class SignupRequest(BaseModel):
    email: str
    password: str


class LoginRequest(BaseModel):
    email: str
    password: str


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


def get_current_user_id(authorization: str | None = Header(default=None)) -> int | None:
    """Returns the authenticated user's id, or None if no/invalid token.
    Used where auth is optional (e.g. /chat works for anonymous users too)."""
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token = authorization[len("Bearer "):]
    return auth.decode_access_token(token)


def require_user_id(authorization: str | None = Header(default=None)) -> int:
    """Same as above, but raises 401 if not authenticated. Used for endpoints
    that require a logged-in user, like /chat/history."""
    user_id = get_current_user_id(authorization)
    if user_id is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return user_id


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


@app.post("/auth/signup", response_model=AuthResponse)
def signup(req: SignupRequest):
    email = req.email.strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="Invalid email")
    if len(req.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    if db.get_user_by_email(email) is not None:
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    password_hash = auth.hash_password(req.password)
    user_id = db.create_user(email, password_hash)
    token = auth.create_access_token(user_id)
    return AuthResponse(access_token=token)


@app.post("/auth/login", response_model=AuthResponse)
def login(req: LoginRequest):
    email = req.email.strip().lower()
    user = db.get_user_by_email(email)
    if user is None or not auth.verify_password(req.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = auth.create_access_token(user["id"])
    return AuthResponse(access_token=token)


@app.get("/chat/history")
def chat_history(user_id: int = Depends(require_user_id)):
    return {"messages": db.get_history(user_id)}


@app.delete("/chat/history")
def delete_chat_history(user_id: int = Depends(require_user_id)):
    db.clear_history(user_id)
    return {"cleared": True}


@app.post("/chat")
def chat_stream(req: ChatRequest, user_id: int | None = Depends(get_current_user_id)):
    """Streams the reply as Server-Sent Events: lines of `data: {"delta": "..."}`.
    If the request is authenticated, both the user's message and the full
    reply are saved to that user's persistent history once streaming completes."""
    messages = build_messages(req)

    def event_generator():
        full_reply = []
        try:
            stream = client.chat.completions.create(
                model=MODEL,
                messages=messages,
                stream=True,
            )
            for chunk in stream:
                delta = chunk.choices[0].delta.content
                if delta:
                    full_reply.append(delta)
                    yield f"data: {json.dumps({'delta': delta})}\n\n"

            if user_id is not None:
                db.add_message(user_id, "user", req.message)
                db.add_message(user_id, "assistant", "".join(full_reply))

            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.post("/chat/sync", response_model=ChatResponse)
def chat_sync(req: ChatRequest, user_id: int | None = Depends(get_current_user_id)):
    """Non-streaming variant: waits for the full reply and returns it as JSON.
    Also persists to history if authenticated."""
    messages = build_messages(req)
    try:
        response = client.chat.completions.create(model=MODEL, messages=messages)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM request failed: {e}")

    reply = response.choices[0].message.content

    if user_id is not None:
        db.add_message(user_id, "user", req.message)
        db.add_message(user_id, "assistant", reply)

    return ChatResponse(reply=reply)


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
