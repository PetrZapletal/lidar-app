"""
iOS App Authentication Module

JWT-based authentication for the iOS app.
This is separate from the admin dashboard auth (auth.py) which uses cookie-based sessions.

For testing purposes, this accepts any credentials and returns a mock user.
"""

import os
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Request, HTTPException, Header
from pydantic import BaseModel, EmailStr
import hashlib
import hmac
import base64
import json

from utils.logger import get_logger

logger = get_logger(__name__)

# Configuration
SECRET_KEY = os.getenv("IOS_AUTH_SECRET_KEY", secrets.token_hex(32))
ACCESS_TOKEN_EXPIRY_HOURS = int(os.getenv("ACCESS_TOKEN_EXPIRY_HOURS", "24"))
REFRESH_TOKEN_EXPIRY_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRY_DAYS", "30"))

router = APIRouter(prefix="/api/v1", tags=["ios-auth"])


# ============================================================================
# Data Models
# ============================================================================

class LoginRequest(BaseModel):
    email: str
    password: str


class RegisterRequest(BaseModel):
    email: str
    password: str
    displayName: Optional[str] = None


class RefreshTokenRequest(BaseModel):
    refreshToken: str


class UserPreferences(BaseModel):
    measurementUnit: str = "meters"
    autoUpload: bool = True
    hapticFeedback: bool = True
    showTutorials: bool = False
    defaultExportFormat: str = "usdz"
    scanQuality: str = "balanced"


class UserResponse(BaseModel):
    id: str
    email: str
    displayName: Optional[str]
    avatarURL: Optional[str] = None
    createdAt: str
    subscription: str
    scanCredits: int
    preferences: UserPreferences


class TokensResponse(BaseModel):
    accessToken: str
    refreshToken: str
    expiresAt: str


class AuthResponse(BaseModel):
    user: UserResponse
    tokens: TokensResponse


class UpdatePreferencesRequest(BaseModel):
    measurementUnit: Optional[str] = None
    autoUpload: Optional[bool] = None
    hapticFeedback: Optional[bool] = None
    showTutorials: Optional[bool] = None
    defaultExportFormat: Optional[str] = None
    scanQuality: Optional[str] = None


# ============================================================================
# Token Management
# ============================================================================

def create_access_token(user_id: str, email: str) -> tuple[str, datetime]:
    """Create a signed access token"""
    expires_at = datetime.utcnow() + timedelta(hours=ACCESS_TOKEN_EXPIRY_HOURS)

    payload = {
        "type": "access",
        "user_id": user_id,
        "email": email,
        "exp": expires_at.isoformat(),
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

    return f"{payload_b64}.{signature}", expires_at


def create_refresh_token(user_id: str) -> str:
    """Create a refresh token"""
    expires_at = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRY_DAYS)

    payload = {
        "type": "refresh",
        "user_id": user_id,
        "exp": expires_at.isoformat(),
        "iat": datetime.utcnow().isoformat()
    }

    payload_json = json.dumps(payload)
    payload_b64 = base64.urlsafe_b64encode(payload_json.encode()).decode()

    signature = hmac.new(
        SECRET_KEY.encode(),
        payload_b64.encode(),
        hashlib.sha256
    ).hexdigest()

    return f"refresh_{payload_b64}.{signature}"


def verify_token(token: str, token_type: str = "access") -> Optional[dict]:
    """Verify and decode a token"""
    try:
        # Handle refresh token prefix
        if token_type == "refresh" and token.startswith("refresh_"):
            token = token[8:]

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

        # Check type
        if payload.get("type") != token_type:
            return None

        # Check expiry
        exp = datetime.fromisoformat(payload["exp"])
        if datetime.utcnow() > exp:
            return None

        return payload

    except Exception as e:
        logger.debug(f"Token verification failed: {e}")
        return None


def get_mock_user(email: str = "test@example.com") -> UserResponse:
    """Get a mock user for testing"""
    return UserResponse(
        id="test-user-1",
        email=email,
        displayName="Test User",
        avatarURL=None,
        createdAt=datetime.utcnow().isoformat(),
        subscription="pro",
        scanCredits=999,
        preferences=UserPreferences()
    )


# ============================================================================
# Authentication Dependency
# ============================================================================

async def get_current_user(authorization: Optional[str] = Header(None)) -> Optional[dict]:
    """Get current user from Authorization header"""
    if not authorization:
        return None

    if not authorization.startswith("Bearer "):
        return None

    token = authorization[7:]
    return verify_token(token, "access")


async def require_auth(authorization: Optional[str] = Header(None)) -> dict:
    """Require authentication - raises 401 if not authenticated"""
    user = await get_current_user(authorization)

    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    return user


# ============================================================================
# Auth Routes
# ============================================================================

@router.post("/auth/login", response_model=AuthResponse)
async def login(request: LoginRequest):
    """
    Login with email and password.

    For testing: accepts any credentials and returns a mock user.
    """
    logger.info(f"Login attempt for: {request.email}")

    # For testing, accept any credentials
    user = get_mock_user(request.email)

    # Create tokens
    access_token, expires_at = create_access_token(user.id, user.email)
    refresh_token = create_refresh_token(user.id)

    logger.info(f"Login successful for: {request.email}")

    return AuthResponse(
        user=user,
        tokens=TokensResponse(
            accessToken=access_token,
            refreshToken=refresh_token,
            expiresAt=expires_at.isoformat()
        )
    )


@router.post("/auth/register", response_model=AuthResponse)
async def register(request: RegisterRequest):
    """
    Register a new user.

    For testing: creates a mock user with the provided email.
    """
    logger.info(f"Registration attempt for: {request.email}")

    # For testing, create mock user
    user = get_mock_user(request.email)
    if request.displayName:
        user = UserResponse(
            id=user.id,
            email=request.email,
            displayName=request.displayName,
            avatarURL=user.avatarURL,
            createdAt=user.createdAt,
            subscription=user.subscription,
            scanCredits=user.scanCredits,
            preferences=user.preferences
        )

    # Create tokens
    access_token, expires_at = create_access_token(user.id, user.email)
    refresh_token = create_refresh_token(user.id)

    logger.info(f"Registration successful for: {request.email}")

    return AuthResponse(
        user=user,
        tokens=TokensResponse(
            accessToken=access_token,
            refreshToken=refresh_token,
            expiresAt=expires_at.isoformat()
        )
    )


@router.post("/auth/refresh", response_model=TokensResponse)
async def refresh_tokens(request: RefreshTokenRequest):
    """Refresh access token using refresh token"""
    payload = verify_token(request.refreshToken, "refresh")

    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    user_id = payload.get("user_id", "test-user-1")

    # Create new tokens
    access_token, expires_at = create_access_token(user_id, "test@example.com")
    refresh_token = create_refresh_token(user_id)

    logger.info(f"Token refresh successful for user: {user_id}")

    return TokensResponse(
        accessToken=access_token,
        refreshToken=refresh_token,
        expiresAt=expires_at.isoformat()
    )


@router.post("/auth/logout")
async def logout(authorization: Optional[str] = Header(None)):
    """Logout - invalidate token (mock implementation)"""
    # In a real implementation, we would blacklist the token
    logger.info("User logged out")
    return {"status": "success", "message": "Logged out successfully"}


@router.post("/auth/forgot-password")
async def forgot_password(email: str):
    """Request password reset (mock implementation)"""
    logger.info(f"Password reset requested for: {email}")
    return {"status": "success", "message": "Password reset email sent"}


@router.post("/auth/apple")
async def apple_sign_in(identityToken: str, authorizationCode: str):
    """Sign in with Apple (mock implementation)"""
    logger.info("Apple Sign In attempt")

    user = get_mock_user("apple-user@example.com")
    access_token, expires_at = create_access_token(user.id, user.email)
    refresh_token = create_refresh_token(user.id)

    return AuthResponse(
        user=user,
        tokens=TokensResponse(
            accessToken=access_token,
            refreshToken=refresh_token,
            expiresAt=expires_at.isoformat()
        )
    )


# ============================================================================
# User Routes
# ============================================================================

@router.get("/users/me", response_model=UserResponse)
async def get_current_user_profile(authorization: Optional[str] = Header(None)):
    """Get current user profile"""
    user_data = await get_current_user(authorization)

    if not user_data:
        raise HTTPException(status_code=401, detail="Unauthorized")

    email = user_data.get("email", "test@example.com")
    return get_mock_user(email)


@router.put("/users/me/preferences")
async def update_preferences(
    request: UpdatePreferencesRequest,
    authorization: Optional[str] = Header(None)
):
    """Update user preferences"""
    user_data = await get_current_user(authorization)

    if not user_data:
        raise HTTPException(status_code=401, detail="Unauthorized")

    logger.info(f"Preferences updated for user: {user_data.get('user_id')}")

    return {"status": "success", "message": "Preferences updated"}


@router.get("/users/me/scans")
async def get_user_scans(authorization: Optional[str] = Header(None)):
    """Get scans for current user"""
    user_data = await get_current_user(authorization)

    if not user_data:
        raise HTTPException(status_code=401, detail="Unauthorized")

    # Import storage service to get scans
    try:
        from services.storage import StorageService
        storage = StorageService()
        scans = await storage.list_scans()
        return scans
    except Exception as e:
        logger.error(f"Error fetching user scans: {e}")
        return []
