"""
SQLite storage for user accounts and persisted chat history.

Uses the stdlib sqlite3 module directly (no ORM) to keep the dependency
footprint small. Opens a fresh connection per call — fine for a
demo/portfolio-scale app; for higher concurrency you'd move to a pooled
connection or a proper client-server database.
"""

import sqlite3
import os
from contextlib import contextmanager

DB_PATH = os.environ.get("DB_PATH", "./chatbot.db")


@contextmanager
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    with get_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
            """
        )


def create_user(email: str, password_hash: str) -> int:
    with get_conn() as conn:
        cur = conn.execute(
            "INSERT INTO users (email, password_hash) VALUES (?, ?)",
            (email, password_hash),
        )
        return cur.lastrowid


def get_user_by_email(email: str) -> sqlite3.Row | None:
    with get_conn() as conn:
        cur = conn.execute("SELECT * FROM users WHERE email = ?", (email,))
        return cur.fetchone()


def get_user_by_id(user_id: int) -> sqlite3.Row | None:
    with get_conn() as conn:
        cur = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        return cur.fetchone()


def add_message(user_id: int, role: str, content: str):
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO messages (user_id, role, content) VALUES (?, ?, ?)",
            (user_id, role, content),
        )


def get_history(user_id: int, limit: int = 100) -> list[dict]:
    with get_conn() as conn:
        cur = conn.execute(
            "SELECT role, content, created_at FROM messages "
            "WHERE user_id = ? ORDER BY id ASC LIMIT ?",
            (user_id, limit),
        )
        return [dict(row) for row in cur.fetchall()]


def clear_history(user_id: int):
    with get_conn() as conn:
        conn.execute("DELETE FROM messages WHERE user_id = ?", (user_id,))
