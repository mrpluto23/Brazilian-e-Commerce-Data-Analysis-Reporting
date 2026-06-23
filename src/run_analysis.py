"""
run_analysis.py
Executes the project's key analysis queries and exports each result set
to data/processed/ as CSV — these feed visualize.py

Run:
    python src/run_analysis.py
"""

import logging
import os

from db_connection import run_query
from config import PROCESSED_DATA_DIR

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

QUERIES = {
    "monthly_orders": """
        SELECT DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
               COUNT(*) AS total_orders
        FROM orders
        WHERE order_status NOT IN ('unavailable', 'canceled')
        GROUP BY 1 ORDER BY 1;
    """,
    "monthly_revenue": """
        SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
               ROUND(SUM(oi.price)::NUMERIC, 2) AS total_revenue
        FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
        WHERE o.order_status NOT IN ('unavailable', 'canceled')
        GROUP BY 1 ORDER BY 1;
    """,
    "top_categories": """
        SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
               COUNT(*) AS items_sold,
               ROUND(SUM(oi.price)::NUMERIC, 2) AS revenue
        FROM order_items oi
        JOIN products p ON p.product_id = oi.product_id
        LEFT JOIN product_category_translation t ON t.product_category_name = p.product_category_name
        GROUP BY 1 ORDER BY revenue DESC LIMIT 15;
    """,
    "sales_by_state": """
        SELECT c.customer_state, COUNT(DISTINCT o.order_id) AS orders,
               ROUND(SUM(oi.price)::NUMERIC, 2) AS revenue
        FROM orders o
        JOIN customers c ON c.customer_id = o.customer_id
        JOIN order_items oi ON oi.order_id = o.order_id
        GROUP BY c.customer_state ORDER BY revenue DESC;
    """,
    "payment_methods": """
        SELECT payment_type, COUNT(*) AS uses,
               ROUND(SUM(payment_value)::NUMERIC, 2) AS total_value
        FROM order_payments GROUP BY payment_type ORDER BY uses DESC;
    """,
    "review_vs_delivery": """
        SELECT r.review_score,
               COUNT(*) AS num_reviews,
               ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400)::NUMERIC, 2) AS avg_delivery_days
        FROM order_reviews r
        JOIN orders o ON o.order_id = r.order_id
        WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
        GROUP BY r.review_score ORDER BY r.review_score;
    """,
}


def run_all() -> None:
    os.makedirs(PROCESSED_DATA_DIR, exist_ok=True)
    for name, sql in QUERIES.items():
        logger.info("Running query: %s", name)
        df = run_query(sql)
        out_path = os.path.join(PROCESSED_DATA_DIR, f"{name}.csv")
        df.to_csv(out_path, index=False)
        logger.info("  -> saved %d rows to %s", len(df), out_path)


if __name__ == "__main__":
    run_all()
