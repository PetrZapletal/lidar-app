"""
Authentication Module

Simple JWT-based authentication for admin dashboard.
"""

import os
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Request, Response, HTTPException, Depends, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
import hashlib
import hmac
import base64
import json

from utils.logger import get_logger

logger = get_logger(__name__)

# Configuration
SECRET_KEY = os.getenv("ADMIN_SECRET_KEY", secrets.token_hex(32))
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD_HASH = os.getenv("ADMIN_PASSWORD_HASH", None)
TOKEN_EXPIRY_HOURS = int(os.getenv("TOKEN_EXPIRY_HOURS", "24"))
COOKIE_NAME = "admin_session"

# Default password (only for development)
DEFAULT_PASSWORD = "lidar2024"

router = APIRouter(tags=["auth"])

# Templates
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))


# ============================================================================
# Password Hashing
# ============================================================================

def hash_password(password: str) -> str:
    """Hash password using SHA-256 with salt"""
    salt = SECRET_KEY[:16]
    return hashlib.sha256(f"{salt}{password}".encode()).hexdigest()


def verify_password(password: str, password_hash: str) -> bool:
    """Verify password against hash"""
    return hmac.compare_digest(hash_password(password), password_hash)


def get_password_hash() -> str:
    """Get the admin password hash"""
    if ADMIN_PASSWORD_HASH:
        return ADMIN_PASSWORD_HASH
    # Use default password hash for development
    return hash_password(DEFAULT_PASSWORD)


# ============================================================================
# Token Management
# ============================================================================

def create_token(username: str) -> str:
    """Create a signed session token"""
    payload = {
        "username": username,
        "exp": (datetime.utcnow() + timedelta(hours=TOKEN_EXPIRY_HOURS)).isoformat(),
        "iat": datetime.utcnow().isoformat()
    }

    # Encode payload
    payload_json = json.dumps(payload)
    payload_b64 = base64.urlsafe_b64encode(payload_json.encode()).decode()

    # Create signature
    signature = hmac.new(
        SECRET_KEY.encode(),
        payload_b64.encode(),
        hashlib.sha256
    ).hexdigest()

    return f"{payload_b64}.{signature}"


def verify_token(token: str) -> Optional[dict]:
    """Verify and decode a session token"""
    try:
        parts = token.split(".")
        if len(parts) != 2:
            return None

        payload_b64, signature = parts

        # Verify signature
        expected_signature = hmac.new(
            SECRET_KEY.encode(),
            payload_b64.encode(),
            hashlib.sha256
        ).hexdigest()

        if not hmac.compare_digest(signature, expected_signature):
            return None

        # Decode payload
        payload_json = base64.urlsafe_b64decode(payload_b64.encode()).decode()
        payload = json.loads(payload_json)

        # Check expiry
        exp = datetime.fromisoformat(payload["exp"])
        if datetime.utcnow() > exp:
            return None

        return payload

    except Exception as e:
        logger.debug(f"Token verification failed: {e}")
        return None


# ============================================================================
# Authentication Dependency
# ============================================================================

async def get_current_user(request: Request) -> Optional[dict]:
    """Get current authenticated user from session cookie"""
    token = request.cookies.get(COOKIE_NAME)

    if not token:
        return None

    return verify_token(token)


async def require_auth(request: Request) -> dict:
    """Require authentication - redirects to login if not authenticated"""
    user = await get_current_user(request)

    if not user:
        raise HTTPException(
            status_code=303,
            headers={"Location": "/login?next=" + str(request.url.path)}
        )

    return user


def auth_required(func):
    """Decorator to require authentication for admin routes"""
    async def wrapper(request: Request, *args, **kwargs):
        user = await get_current_user(request)
        if not user:
            return RedirectResponse(
                url=f"/login?next={request.url.path}",
                status_code=303
            )
        return await func(request, *args, **kwargs)

    wrapper.__name__ = func.__name__
    return wrapper


# ============================================================================
# Routes
# ============================================================================

@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request, next: str = "/admin", error: str = None):
    """Login page"""
    # Check if already logged in
    user = await get_current_user(request)
    if user:
        return RedirectResponse(url=next, status_code=303)

    return templates.TemplateResponse("login.html", {
        "request": request,
        "next": next,
        "error": error
    })


@router.post("/login")
async def login(
    request: Request,
    response: Response,
    username: str = Form(...),
    password: str = Form(...),
    next: str = Form("/admin")
):
    """Process login"""
    # Verify credentials
    if username != ADMIN_USERNAME:
        return RedirectResponse(
            url=f"/login?next={next}&error=invalid",
            status_code=303
        )

    if not verify_password(password, get_password_hash()):
        logger.warning(f"Failed login attempt for user: {username}")
        return RedirectResponse(
            url=f"/login?next={next}&error=invalid",
            status_code=303
        )

    # Create session token
    token = create_token(username)

    # Set cookie and redirect
    response = RedirectResponse(url=next, status_code=303)
    response.set_cookie(
        key=COOKIE_NAME,
        value=token,
        httponly=True,
        secure=False,  # Set to True in production with HTTPS
        samesite="lax",
        max_age=TOKEN_EXPIRY_HOURS * 3600
    )

    logger.info(f"User logged in: {username}")

    return response


@router.get("/logout")
async def logout(request: Request):
    """Logout and clear session"""
    response = RedirectResponse(url="/login", status_code=303)
    response.delete_cookie(key=COOKIE_NAME)

    logger.info("User logged out")

    return response


@router.get("/api/auth/check")
async def check_auth(request: Request):
    """Check if user is authenticated (for AJAX)"""
    user = await get_current_user(request)

    if user:
        return {
            "authenticated": True,
            "username": user["username"]
        }

    return {"authenticated": False}
