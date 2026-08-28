"""Runtime configuration, read from the environment."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    env: str
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    db_pool_size: int
    log_level: str

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+psycopg://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )

    @property
    def safe_database_url(self) -> str:
        """Same URL with the password blanked out, for logs."""
        return (
            f"postgresql+psycopg://{self.db_user}:***"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


def load_settings() -> Settings:
    return Settings(
        env=os.getenv("APP_ENV", "local"),
        db_host=os.getenv("DB_HOST", "localhost"),
        db_port=int(os.getenv("DB_PORT", "5432")),
        db_name=os.getenv("DB_NAME", "tasksdb"),
        db_user=os.getenv("DB_USER", "tasks"),
        db_password=os.getenv("DB_PASSWORD", ""),
        db_pool_size=int(os.getenv("DB_POOL_SIZE", "5")),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
    )


settings = load_settings()
