from abc import ABC, abstractmethod
from app.domain.user import User


class UserRepository(ABC):
    @abstractmethod
    async def find_by_email(self, email: str) -> User | None:
        pass

    @abstractmethod
    async def find_by_id(self, id: str) -> User | None:
        pass

    @abstractmethod
    async def save(self, user: User) -> User:
        pass
