from app.models.request import UpdateProfileRequest
from app.models.response import UserResponse, HiveListResponse


class UserService:
    async def get_profile(self, user_id: str) -> UserResponse:
        # TODO: implement with UserRepositoryImpl
        raise NotImplementedError

    async def update_profile(self, user_id: str, body: UpdateProfileRequest) -> UserResponse:
        # TODO: implement with UserRepositoryImpl
        raise NotImplementedError

    async def get_hives(self, user_id: str) -> HiveListResponse:
        # TODO: implement with HiveRepositoryImpl
        raise NotImplementedError
