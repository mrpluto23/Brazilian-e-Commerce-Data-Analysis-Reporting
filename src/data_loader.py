"""
data_loader.py
It loads the OList CSVs into PostgreSQL using pandas + SQLAlchemy.
Its workflow is basically same as sql/02_load_data.sql
"""

import logging 
import os 
import pandas as pd

from config import RAW_DATA_DIR, DB_Config
from db_connection import get_engine, run_query, run_sql_file, test_connection

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# Maps: target SQL table -> (csv filename, columns to load in DB column order)
TABLE_FILE_MAP = {
    "product_category_translation": (
        "product_category_name_translation.csv",
        ["product_category_name", "product_category_name_english"],
    ),
    "customers": (
        "olist_customers_dataset.csv",
        ["customer_id", "customer_unique_id", "customer_zip_code_prefix",
         "customer_city", "customer_state"],
    ),
    "sellers": (
        "olist_sellers_dataset.csv",
        ["seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"],
    ),
    "geolocation": (
        "olist_geolocation_dataset.csv",
        ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng",
         "geolocation_city", "geolocation_state"],
    ),
    "products": (
        "olist_products_dataset.csv",
        ["product_id", "product_category_name", "product_name_length",
         "product_description_length", "product_photos_qty", "product_weight_g",
         "product_length_cm", "product_height_cm", "product_width_cm"],
    ),
    "orders": (
        "olist_orders_dataset.csv",
        ["order_id", "customer_id", "order_status", "order_purchase_timestamp",
         "order_approved_at", "order_delivered_carrier_date",
         "order_delivered_customer_date", "order_estimated_delivery_date"],
    ),
    "order_items": (
        "olist_order_items_dataset.csv",
        ["order_id", "order_item_id", "product_id", "seller_id",
         "shipping_limit_date", "price", "freight_value"],
    ),
    "order_payments": (
        "olist_order_payments_dataset.csv",
        ["order_id", "payment_sequential", "payment_type",
         "payment_installments", "payment_value"],
    ),
    "order_reviews": (
        "olist_order_reviews_dataset.csv",
        ["review_id", "order_id", "review_score", "review_comment_title",
         "review_comment_message", "review_creation_date", "review_answer_timestamp"],
    ),
}

# Raw CSV header names 
RAW_PRODUCTS_COLUMN_RENAME = {
    "product_name_lenght": "product_name_length",
    "product_description_lenght": "product_description_length",
}

DATE_COLUMNS = {
    "orders": ["order_purchase_timestamp", "order_approved_at",
               "order_delivered_carrier_date", "order_delivered_customer_date",
               "order_estimated_delivery_date"],
    "order_items": ["shipping_limit_date"],
    "order_reviews": ["review_creation_date", "review_answer_timestamp"],
}

# Load order respects FK dependencies (parents before children)
LOAD_ORDER = [
    "product_category_translation", "customers", "sellers", "geolocation",
    "products", "orders", "order_items", "order_payments", "order_reviews",
]
def backfill_missing_categories(df_products: pd.DataFrame) -> None:
    """
    olist_products_dataset.csv contains a few product_category_name values
    (e.g. 'pc_gamer') that are missing from olist_category_name_translation.csv.
    Insert those into product_category_translation using the original name as
    a fallback English label, so the FK on products doesn't reject real rows.
    """
    engine = get_engine()
    categories_in_products = set(df_products["product_category_name"].dropna().unique())
    existing = set(run_query(
        "SELECT product_category_name FROM product_category_translation"
    )["product_category_name"])
    missing = categories_in_products - existing
    if missing:
        logger.warning(
            "%d category name(s) missing from the translation CSV (known Kaggle "
            "dataset gap, e.g. 'pc_gamer'); backfilling with the original name as "
            "a fallback English label: %s", len(missing), sorted(missing),
        )
        backfill_df = pd.DataFrame({
            "product_category_name": sorted(missing),
            "product_category_name_english": sorted(missing),
        })
        backfill_df.to_sql("product_category_translation", engine, if_exists="append", index=False)

def load_table(table_name: str) -> int:
    filename, columns = TABLE_FILE_MAP[table_name]
    path = os.path.join(RAW_DATA_DIR, filename)

    if not os.path.exists(path):
        logger.warning("Skipping %s — file not found at %s. Download the "
                        "Kaggle dataset into data/raw/ first.", table_name, path)
        return 0

    df = pd.read_csv(path)
    # Add this immediately after the CSV is read into the 'df' variable:
    df.rename(columns={
    'product_name_lenght': 'product_name_length',
    'product_description_lenght': 'product_description_length'
    }, inplace=True)
    
    df = df[columns]

    if table_name == "products":
        backfill_missing_categories(df)
        df = df.rename(columns=RAW_PRODUCTS_COLUMN_RENAME)

    # Parse date columns explicitly so they load as proper TIMESTAMP, not text
    for col in DATE_COLUMNS.get(table_name, []):
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")

    df = df[columns]  # enforce column order matching the SQL schema

    engine = get_engine()
    
    # Deduplicate review_id to prevent Primary Key violations
    if 'review_id' in df.columns:
        df.drop_duplicates(subset=['review_id'], inplace=True)


    df.to_sql(table_name, engine, if_exists="append", index=False, chunksize=5000)
    logger.info("Loaded %d rows into %s", len(df), table_name)
    return len(df)


def load_all() -> None:
    if not test_connection():
        raise RuntimeError(
            "Could not connect to the database. Check your .env / "
            "OLIST_DB_* environment variables and that PostgreSQL is running."
        )

    logger.info("Applying schema (sql/01_schema.sql)...")
    run_sql_file("sql/01_schema.sql")

    total = 0
    for table in LOAD_ORDER:
        total += load_table(table)

    logger.info("Load complete. %d total rows inserted.", total)
    logger.info("Run sql/03_validation_queries.sql next to verify the import.")


if __name__ == "__main__":
    load_all()
