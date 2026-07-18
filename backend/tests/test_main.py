"""
Backend tests. LLM calls and RAG embedding are mocked so these run
offline, without an API key and without downloading the embedding model.
Run with: pytest
"""

import os
import sys
import json
from unittest.mock import patch, MagicMock

os.environ.setdefault("LLM_API_KEY", "test-key")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient


def make_client():
    import main
    return TestClient(main.app)


def test_health():
    client = make_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_chat_sync_success():
    client = make_client()

    fake_response = MagicMock()
    fake_response.choices = [MagicMock(message=MagicMock(content="Hi there!"))]

    with patch("main.client.chat.completions.create", return_value=fake_response):
        response = client.post("/chat/sync", json={"message": "hello", "history": []})

    assert response.status_code == 200
    assert response.json() == {"reply": "Hi there!"}


def test_chat_sync_llm_failure_returns_502():
    client = make_client()

    with patch("main.client.chat.completions.create", side_effect=Exception("boom")):
        response = client.post("/chat/sync", json={"message": "hello", "history": []})

    assert response.status_code == 502
    assert "LLM request failed" in response.json()["detail"]


def test_chat_stream_yields_deltas():
    client = make_client()

    def fake_chunk(text):
        chunk = MagicMock()
        chunk.choices = [MagicMock(delta=MagicMock(content=text))]
        return chunk

    fake_stream = [fake_chunk("Hel"), fake_chunk("lo!")]

    with patch("main.client.chat.completions.create", return_value=iter(fake_stream)):
        with client.stream("POST", "/chat", json={"message": "hi", "history": []}) as response:
            assert response.status_code == 200
            events = [line for line in response.iter_lines() if line.startswith("data:")]

    payloads = [json.loads(line[len("data: "):]) for line in events]
    deltas = [p["delta"] for p in payloads if "delta" in p]
    assert deltas == ["Hel", "lo!"]
    assert any(p.get("done") for p in payloads)


def test_ingest_text_and_status():
    client = make_client()

    with patch("rag.ingest_text", return_value=2) as mock_ingest:
        response = client.post("/ingest/text", json={"text": "some content", "source": "test"})
    assert response.status_code == 200
    assert response.json() == {"chunks_added": 2}
    mock_ingest.assert_called_once()

    with patch("rag.has_documents", return_value=True):
        response = client.get("/ingest/status")
    assert response.json() == {"has_documents": True}
