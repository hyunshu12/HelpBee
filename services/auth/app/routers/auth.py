from fastapi import APIRouter, Depends, HTTPException, status
from app.models.request import LoginRequest, RegisterRequest
from app.models.response import TokenResponse
from app.services.auth_service import AuthService

router = APIRouter(tags=["auth"])


def get_auth_service() -> AuthService:
    return AuthService()


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    body: RegisterRequest,
    service: AuthService = Depends(get_auth_service),
):
    return await service.register(body)


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    service: AuthService = Depends(get_auth_service),
):
    return await service.login(body)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    refresh_token: str,
    service: AuthService = Depends(get_auth_service),
):
    return await service.refresh(refresh_token)
