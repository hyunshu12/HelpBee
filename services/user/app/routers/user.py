from fastapi import APIRouter, Depends
from app.models.request import UpdateProfileRequest
from app.models.response import UserResponse, HiveListResponse
from app.services.user_service import UserService

router = APIRouter(tags=["users"])


def get_user_service() -> UserService:
    return UserService()


@router.get("/me", response_model=UserResponse)
async def get_profile(
    user_id: str,
    service: UserService = Depends(get_user_service),
):
    return await service.get_profile(user_id)


@router.patch("/me", response_model=UserResponse)
async def update_profile(
    user_id: str,
    body: UpdateProfileRequest,
    service: UserService = Depends(get_user_service),
):
    return await service.update_profile(user_id, body)


@router.get("/me/hives", response_model=HiveListResponse)
async def get_hives(
    user_id: str,
    service: UserService = Depends(get_user_service),
):
    return await service.get_hives(user_id)
