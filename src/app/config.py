import os
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Model config to read from env case-insensitively
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    # Core parameters
    llm_url: str = "http://localhost:11434"
    llm_model: str = "qwen2.5:0.5b"
    
    qdrant_url: str = "http://localhost:6333"
    qdrant_collection: str = "knowledge_base"

    # API credentials / security
    api_key: str = "default-dev-key"

settings = Settings()
