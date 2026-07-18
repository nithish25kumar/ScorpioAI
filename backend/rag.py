"""
Minimal RAG (Retrieval-Augmented Generation) layer using ChromaDB.

- ingest_text(): chunks and stores a document
- retrieve(): returns the top-k most relevant chunks for a query

Uses ChromaDB's built-in default embedding function (all-MiniLM-L6-v2,
runs locally via onnxruntime) so no extra embedding API/key is needed.
"""

import chromadb
import uuid

CHROMA_DIR = "./chroma_db"
COLLECTION_NAME = "documents"
CHUNK_SIZE = 800  # characters per chunk
CHUNK_OVERLAP = 100

_client = chromadb.PersistentClient(path=CHROMA_DIR)
_collection = _client.get_or_create_collection(name=COLLECTION_NAME)


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split text into overlapping chunks so context isn't cut mid-thought."""
    text = text.strip()
    if not text:
        return []

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunks.append(text[start:end])
        start += chunk_size - overlap
    return chunks


def ingest_text(text: str, source: str = "upload") -> int:
    """Chunk and store a document's text. Returns number of chunks stored."""
    chunks = chunk_text(text)
    if not chunks:
        return 0

    ids = [str(uuid.uuid4()) for _ in chunks]
    metadatas = [{"source": source} for _ in chunks]
    _collection.add(documents=chunks, ids=ids, metadatas=metadatas)
    return len(chunks)


def retrieve(query: str, top_k: int = 3) -> list[str]:
    """Return the top_k most relevant chunks for a query. Empty list if no documents yet."""
    if _collection.count() == 0:
        return []

    results = _collection.query(query_texts=[query], n_results=min(top_k, _collection.count()))
    documents = results.get("documents", [[]])
    return documents[0] if documents else []


def has_documents() -> bool:
    return _collection.count() > 0


def clear_all():
    """Wipe all ingested documents (useful for tests / resetting)."""
    global _collection
    _client.delete_collection(COLLECTION_NAME)
    _collection = _client.get_or_create_collection(name=COLLECTION_NAME)
