"""
db_connection.py
SQLAlchemy engine + small helpers for executing queries
"""

import logging
from contextlib import contextmanager

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from config import DB_Config

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

_engine: Engine | None = None


def get_engine() -> Engine:
    """Return a singleton SQLAlchemy engine, creating it on first call."""
    global _engine
    if _engine is None:
        logger.info("Creating SQLAlchemy engine for %s", DB_Config.name)
        _engine = create_engine(DB_Config.sqlalchemy_url, pool_pre_ping=True)
    return _engine


@contextmanager
def get_connection():
    """Context-managed raw connection, e.g. for running .sql script files."""
    engine = get_engine()
    conn = engine.connect()
    try:
        yield conn
    finally:
        conn.close()


def run_query(sql: str, params: dict | None = None) -> pd.DataFrame:
    """Run a SELECT query and return the result as a pandas DataFrame."""
    engine = get_engine()
    with engine.connect() as conn:
        return pd.read_sql(text(sql), conn, params=params)


def run_sql_file(filepath: str) -> None:
    """
    Execute every statement in a .sql file against the database.
    Splits on semicolons — adequate for this project's scripts, which
    don't contain semicolons inside string literals or PL/pgSQL bodies.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        raw_sql = f.read()

    statements = [s.strip() for s in raw_sql.split(";") if s.strip() and not s.strip().startswith("--")]

    engine = get_engine()
    with engine.begin() as conn:
        for stmt in statements:
            logger.debug("Executing: %s...", stmt[:80].replace("\n", " "))
            conn.execute(text(stmt))
    logger.info("Executed %d statements from %s", len(statements), filepath)


def test_connection() -> bool:
    """Quick sanity check used by CI and by developers after first setup."""
    try:
        df = run_query("SELECT 1 AS ok;")
        return bool(df.loc[0, "ok"] == 1)
    except Exception as exc:  # noqa: BLE001
        logger.error("Database connection failed: %s", exc)
        return False


if __name__ == "__main__":
    ok = test_connection()
    print("Connection OK" if ok else "Connection FAILED — check .env / config.py")