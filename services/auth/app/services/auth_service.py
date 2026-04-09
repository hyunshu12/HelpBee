import uuid
from datetime import datetime
from fastapi import HTTPException, status

from app.domain.user import User
from app.models.request import LoginRequest, RegisterRequest
from app.models.response import TokenResponse


class AuthService:
    async def register(self, body: RegisterRequest) -> TokenResponse:
        # TODO: implement with UserRepositoryImpl
        raise NotImplementedError

    async def login(self, body: LoginRequest) -> TokenResponse:
        # TODO: implement with UserRepositoryImpl
        raise NotImplementedError

    async def refresh(self, refresh_token: str) -> TokenResponse:
        # TODO: implement JWT refresh
        raise NotImplementedError
