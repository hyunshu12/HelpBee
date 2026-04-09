from pydantic import BaseModel, HttpUrl


class AnalyzeRequest(BaseModel):
    hive_id: str
    user_id: str
    image_url: HttpUrl
