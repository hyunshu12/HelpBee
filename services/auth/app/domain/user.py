from dataclasses import dataclass
from datetime import datetime


@dataclass
class User:
    id: str
    email: str
    hashed_password: str
    name: str
    is_active: bool
    created_at: datetime
    updated_at: datetime
