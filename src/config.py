"""
config.py
Main configuration for the project. It reads Database credentials from the environment variables
so confidential data never committed to GitHub

Usage:
Setting .env variables before running is the only prerequisite
"""

import os
from dataclasses import dataclass

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

@dataclass(frozen=True)
class DB_Config:
    host: str = os.getenv("OLIST_DB_HOST", "localhost")
    port: int = int(os.getenv("OLIST_DB_PORT", "5432"))
    name: str = os.getenv("OLIST_DB_NAME", "olist_db")
    user: str = os.getenv("OLIST_DB_USER", "kamal")
    password: str = os.getenv("OLIST_DB_PASSWORD", "userpasswd")

    @property
    def sqlalchemy_url(self) -> str:
        return f"postgresql+psycopg2://{self.user}:{self.password}@{self.host}:{self.port}/{self.name}"
    
#paths
RAW_DATA_DIR = "data/raw"
PROCESSED_DATA_DIR = "data/processed"
SQL_DIR = "sql/"
OUTPUT_CHARTS_DIR = "outputs/charts"
