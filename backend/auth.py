"""
Authentication helpers: password hashing (stdlib pbkdf2, no native deps)
and JWT access tokens (PyJWT, pure Python — avoids the native/Rust build
issues that packages like passlib[bcrypt] or python-jose can hit on
newer Python versions without prebuilt wheels).
"""

import os
import hashlib
import hmac
import secrets
import time
import jwt

SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "dev-secret-change-in-production")
TOKEN_TTL_SECONDS = 60 * 60 * 24 * 7  # 7 days
PBKDF2_ITERATIONS = 260_000


def hash_password(password: str) -> str:
    """Returns 'salt_hex$hash_hex'."""
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), PBKDF2_ITERATIONS)
    return f"{salt}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        salt, expected_hex = stored.split("$")
    except ValueError:
        return False
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), PBKDF2_ITERATIONS)
    return hmac.compare_digest(digest.hex(), expected_hex)


def create_access_token(user_id: int) -> str:
    payload = {"sub": str(user_id), "exp": int(time.time()) + TOKEN_TTL_SECONDS}
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")


def decode_access_token(token: str) -> int | None:
    """Returns the user_id encoded in the token, or None if invalid/expired."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        return int(payload["sub"])
    except jwt.PyJWTError:
        return None
