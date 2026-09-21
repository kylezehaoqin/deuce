"""Single source of truth for configuration. Everything else imports `settings`."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=REPO_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    postgres_host: str = "localhost"
    postgres_port: int = 5433
    postgres_db: str = "tennis"
    postgres_user: str = "tennis"
    postgres_password: str = "tennis"

    data_dir: Path = Path("data/raw")
    mcp_base_url: str = (
        "https://raw.githubusercontent.com/JeffSackmann/tennis_MatchChartingProject/master"
    )

    @property
    def dsn(self) -> str:
        return (
            f"postgresql://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )

    @property
    def data_path(self) -> Path:
        p = self.data_dir
        return p if p.is_absolute() else REPO_ROOT / p


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
