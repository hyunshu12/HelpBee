from pydantic import BaseModel
from datetime import datetime
from typing import List, Optional


class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    phone: Optional[str]
    farm_name: Optional[str]
    farm_location: Optional[str]
    created_at: datetime


class HiveResponse(BaseModel):
    id: str
    name: str
    location: str
    created_at: datetime


class HiveListResponse(BaseModel):
    items: List[HiveResponse]
    total: int
