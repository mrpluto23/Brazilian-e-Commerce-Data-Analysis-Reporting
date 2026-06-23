"""
visualize.py
Generates every chart in the project and saves them as PNGs in outputs/charts/.

Run:
    python src/visualize.py
"""

import logging
import os

import matplotlib.pyplot as plt
import seaborn as sns

from db_connection import run_query
from config import OUTPUT_CHARTS_DIR

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

sns.set_theme(style="whitegrid")
plt.rcParams["figure.figsize"] = (10, 6)
plt.rcParams["savefig.dpi"] = 150


def save(fig, name: str) -> None:
    os.makedirs(OUTPUT_CHARTS_DIR, exist_ok=True)
    path = os.path.join(OUTPUT_CHARTS_DIR, f"{name}.png")
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    logger.info("Saved %s", path)


def chart_revenue_trend():
    """Line chart — revenue trend over time. Best for showing a continuous
    time series and visually spotting seasonality/growth."""
    df = run_query("""
        SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS month,
               SUM(oi.price) AS revenue
        FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
        WHERE o.order_status NOT IN ('unavailable','canceled')
        GROUP BY 1 ORDER BY 1;
    """)
    fig, ax = plt.subplots()
    ax.plot(df["month"], df["revenue"], marker="o", linewidth=2)
    ax.set_title("Monthly Revenue Trend")
    ax.set_xlabel("Month")
    ax.set_ylabel("Revenue (BRL)")
    fig.autofmt_xdate()
    save(fig, "01_revenue_trend")


def chart_orders_by_month():
    """Bar chart — order volume by month. Bars suit discrete period counts
    better than a line when the audience cares about individual months."""
    df = run_query("""
        SELECT DATE_TRUNC('month', order_purchase_timestamp)::DATE AS month,
               COUNT(*) AS orders
        FROM orders
        WHERE order_status NOT IN ('unavailable','canceled')
        GROUP BY 1 ORDER BY 1;
    """)
    fig, ax = plt.subplots()
    ax.bar(df["month"], df["orders"], color="#3b82f6")
    ax.set_title("Orders by Month")
    ax.set_xlabel("Month")
    ax.set_ylabel("Number of Orders")
    fig.autofmt_xdate()
    save(fig, "02_orders_by_month")


def chart_category_performance():
    """Horizontal bar chart — top categories by revenue. Horizontal bars
    handle long category-name labels far better than vertical bars."""
    df = run_query("""
        SELECT COALESCE(t.product_category_name_english, p.product_category_name) AS category,
               SUM(oi.price) AS revenue
        FROM order_items oi
        JOIN products p ON p.product_id = oi.product_id
        LEFT JOIN product_category_translation t ON t.product_category_name = p.product_category_name
        GROUP BY 1 ORDER BY revenue DESC LIMIT 10;
    """)
    fig, ax = plt.subplots()
    ax.barh(df["category"][::-1], df["revenue"][::-1], color="#10b981")
    ax.set_title("Top 10 Product Categories by Revenue")
    ax.set_xlabel("Revenue (BRL)")
    save(fig, "03_category_performance")


def chart_geographic_distribution():
    """Bar chart — revenue by customer state. A choropleth map would be
    ideal but requires shapefiles; a ranked bar chart is the pragmatic,
    dependency-light substitute that still ranks states clearly."""
    df = run_query("""
        SELECT c.customer_state AS state, SUM(oi.price) AS revenue
        FROM orders o
        JOIN customers c ON c.customer_id = o.customer_id
        JOIN order_items oi ON oi.order_id = o.order_id
        GROUP BY 1 ORDER BY revenue DESC LIMIT 15;
    """)
    fig, ax = plt.subplots()
    ax.bar(df["state"], df["revenue"], color="#f59e0b")
    ax.set_title("Revenue by Customer State (Top 15)")
    ax.set_xlabel("State")
    ax.set_ylabel("Revenue (BRL)")
    save(fig, "04_geographic_distribution")


def chart_payment_breakdown():
    """Pie chart — payment method share. Pie charts work here because
    there are few categories (4-5) and the message is "share of whole.\""""
    df = run_query("""
        SELECT payment_type, COUNT(*) AS uses
        FROM order_payments GROUP BY payment_type ORDER BY uses DESC;
    """)
    fig, ax = plt.subplots()
    ax.pie(df["uses"], labels=df["payment_type"], autopct="%1.1f%%", startangle=90)
    ax.set_title("Payment Method Breakdown")
    save(fig, "05_payment_breakdown")


def chart_review_distribution():
    """Bar chart — review score distribution. Shows the shape of customer
    sentiment at a glance (Olist reviews are heavily skewed toward 5)."""
    df = run_query("SELECT review_score, COUNT(*) AS n FROM order_reviews GROUP BY 1 ORDER BY 1;")
    fig, ax = plt.subplots()
    ax.bar(df["review_score"], df["n"], color="#ef4444")
    ax.set_title("Review Score Distribution")
    ax.set_xlabel("Review Score (1-5)")
    ax.set_ylabel("Number of Reviews")
    save(fig, "06_review_distribution")


def chart_delivery_vs_review():
    """Box plot — delivery time distribution per review score. Box plots
    reveal spread/outliers, which a simple bar of averages would hide —
    important here since delivery-time variance is the real story."""
    df = run_query("""
        SELECT r.review_score,
               EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400 AS delivery_days
        FROM order_reviews r
        JOIN orders o ON o.order_id = r.order_id
        WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
          AND EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400 < 60;
    """)
    fig, ax = plt.subplots()
    sns.boxplot(data=df, x="review_score", y="delivery_days", ax=ax)
    ax.set_title("Delivery Time by Review Score")
    ax.set_xlabel("Review Score")
    ax.set_ylabel("Delivery Time (days)")
    save(fig, "07_delivery_vs_review")


def generate_all():
    chart_revenue_trend()
    chart_orders_by_month()
    chart_category_performance()
    chart_geographic_distribution()
    chart_payment_breakdown()
    chart_review_distribution()
    chart_delivery_vs_review()
    logger.info("All charts generated in %s", OUTPUT_CHARTS_DIR)


if __name__ == "__main__":
    generate_all()