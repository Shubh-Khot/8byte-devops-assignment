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
    # RDS (and the NAT idle timeout in front of it) will silently drop
    # connections that have been idle a while. Without pre_ping the first
    # request after a quiet period fails with "server closed the connection".
    pool_pre_ping=True,
    pool_recycle=1800,
    connect_args={"connect_timeout": 5},
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


# Arbitrary but fixed: every process that might touch the schema must agree
# on the same key for the lock to mean anything.
_SCHEMA_LOCK_KEY = 8_271_004


def init_schema() -> None:
    """Create tables if they are missing, one process at a time.

    create_all() is not safe to run concurrently. Two uvicorn workers booting
    together will both see "no tables", both issue CREATE TABLE, and the loser
    gets a UniqueViolation on pg_class. A Postgres advisory lock serialises
    them: the second worker waits, then finds the tables already there.

    Fine for a single-table demo. A real service would use Alembic and run
    migrations as a one-shot ECS task before the rolling update, so the
    application containers never touch DDL at all.
    """
    with engine.begin() as conn:
        # Transaction-scoped: released on commit, and released automatically
        # if the process dies mid-migration instead of wedging every future boot.
        conn.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _SCHEMA_LOCK_KEY})
        Base.metadata.create_all(conn)

    log.info("schema ready", extra={"db": settings.safe_database_url})


def ping() -> None:
    """Raise if the database is not reachable. Used by the readiness probe."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
