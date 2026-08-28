import logging

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from config import settings
from models import Base

log = logging.getLogger(__name__)

engine = create_engine(
    settings.database_url,
    pool_size=settings.db_pool_size,
    max_overflow=2,
    pool_pre_ping=True,
    pool_recycle=1800,
    connect_args={"connect_timeout": 5},
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

_SCHEMA_LOCK_KEY = 8_271_004


def init_schema() -> None:
    """Create the tables, one process at a time.

    create_all() is not concurrency safe: two workers booting together both
    see no tables, both issue CREATE TABLE, and one gets a UniqueViolation.
    The advisory lock makes the second worker wait and find them already there.
    """
    with engine.begin() as conn:
        conn.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _SCHEMA_LOCK_KEY})
        Base.metadata.create_all(conn)

    log.info("schema ready", extra={"db": settings.safe_database_url})


def ping() -> None:
    """Raise if the database is unreachable."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
