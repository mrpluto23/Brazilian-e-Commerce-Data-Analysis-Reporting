-- =====================================================================
-- 04_analysis_queries.sql
-- Core analytical queries required by the project brief.
-- Each block is self-contained, documented, and ordered for readability.
-- Designed for PostgreSQL (uses DATE_TRUNC, generate_series, etc.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Monthly order trends — order volume by month
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
    COUNT(*) AS total_orders
FROM orders
WHERE order_status NOT IN ('unavailable', 'canceled')
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q2. Monthly revenue trends — sum of item price (excludes freight)
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
    ROUND(SUM(oi.price)::NUMERIC, 2)                      AS total_revenue,
    ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2)   AS total_revenue_incl_freight
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('unavailable', 'canceled')
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q3. Top-selling product categories (by item volume)
-- ---------------------------------------------------------------------
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    COUNT(*) AS items_sold
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN product_category_translation t ON t.product_category_name = p.product_category_name
GROUP BY 1
ORDER BY items_sold DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q4. Revenue by product category
-- ---------------------------------------------------------------------
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    ROUND(SUM(oi.price)::NUMERIC, 2) AS category_revenue,
    ROUND(AVG(oi.price)::NUMERIC, 2) AS avg_item_price
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN product_category_translation t ON t.product_category_name = p.product_category_name
GROUP BY 1
ORDER BY category_revenue DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q5. Sales distribution by state and city (customer location)
-- ---------------------------------------------------------------------
-- 5a. By state
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.price)::NUMERIC, 2) AS revenue
FROM orders o
JOIN customers c   ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_state
ORDER BY revenue DESC;

-- 5b. By city (top 20)
SELECT
    c.customer_city,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.price)::NUMERIC, 2) AS revenue
FROM orders o
JOIN customers c   ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_city, c.customer_state
ORDER BY revenue DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- Q6. Seller performance analysis
-- ---------------------------------------------------------------------
SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id)       AS orders_fulfilled,
    ROUND(SUM(oi.price)::NUMERIC, 2)  AS total_sales,
    ROUND(AVG(r.review_score)::NUMERIC, 2) AS avg_review_score
FROM order_items oi
JOIN sellers s ON s.seller_id = oi.seller_id
LEFT JOIN order_reviews r ON r.order_id = oi.order_id
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(DISTINCT oi.order_id) >= 5      -- exclude near-zero-volume sellers
ORDER BY total_sales DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- Q7. Customer purchasing behavior — orders & spend per unique customer
-- ---------------------------------------------------------------------
SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id)        AS total_orders,
    ROUND(SUM(oi.price)::NUMERIC, 2)  AS total_spend,
    ROUND(AVG(oi.price)::NUMERIC, 2)  AS avg_item_price,
    MIN(o.order_purchase_timestamp)   AS first_purchase,
    MAX(o.order_purchase_timestamp)   AS last_purchase
FROM customers c
JOIN orders o     ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_unique_id
ORDER BY total_spend DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- Q8. Payment method usage rates
-- ---------------------------------------------------------------------
SELECT
    payment_type,
    COUNT(*) AS uses,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all_payments,
    ROUND(AVG(payment_installments)::NUMERIC, 2)       AS avg_installments,
    ROUND(SUM(payment_value)::NUMERIC, 2)              AS total_value
FROM order_payments
GROUP BY payment_type
ORDER BY uses DESC;

-- ---------------------------------------------------------------------
-- Q9. Delivery time analysis (purchase -> customer delivery, in days)
-- ---------------------------------------------------------------------
SELECT
    ROUND(AVG(EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400)::NUMERIC, 2) AS avg_delivery_days,
    ROUND(AVG(EXTRACT(EPOCH FROM (order_estimated_delivery_date - order_purchase_timestamp)) / 86400)::NUMERIC, 2) AS avg_estimated_days,
    ROUND(AVG(EXTRACT(EPOCH FROM (order_delivered_customer_date - order_estimated_delivery_date)) / 86400)::NUMERIC, 2) AS avg_days_late_or_early
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

-- Delivery time distribution by destination state
SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400)::NUMERIC, 1) AS avg_delivery_days
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;

-- ---------------------------------------------------------------------
-- Q10. Relationship between review scores and delivery performance
-- ---------------------------------------------------------------------
SELECT
    r.review_score,
    COUNT(*) AS num_reviews,
    ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400)::NUMERIC, 2) AS avg_delivery_days,
    ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date)) / 86400)::NUMERIC, 2) AS avg_days_late_vs_estimate
FROM order_reviews r
JOIN orders o ON o.order_id = r.order_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;

-- ---------------------------------------------------------------------
-- Q11. Average order value (AOV)
-- ---------------------------------------------------------------------
WITH order_totals AS (
    SELECT o.order_id, SUM(oi.price + oi.freight_value) AS order_value
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('unavailable', 'canceled')
    GROUP BY o.order_id
)
SELECT
    ROUND(AVG(order_value)::NUMERIC, 2)     AS avg_order_value,
    ROUND(MIN(order_value)::NUMERIC, 2)     AS min_order_value,
    ROUND(MAX(order_value)::NUMERIC, 2)     AS max_order_value,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY order_value)::NUMERIC, 2) AS median_order_value
FROM order_totals;

-- AOV trend by month
WITH order_totals AS (
    SELECT o.order_id, o.order_purchase_timestamp,
           SUM(oi.price + oi.freight_value) AS order_value
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('unavailable', 'canceled')
    GROUP BY o.order_id, o.order_purchase_timestamp
)
SELECT
    DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
    ROUND(AVG(order_value)::NUMERIC, 2) AS avg_order_value,
    COUNT(*) AS orders
FROM order_totals
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q12. Customer retention and repeat purchase analysis
-- ---------------------------------------------------------------------
WITH customer_order_counts AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS num_orders
    FROM customers c
    JOIN orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE WHEN num_orders = 1 THEN 'one-time buyer' ELSE 'repeat buyer (2+)' END AS segment,
    COUNT(*) AS num_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers
FROM customer_order_counts
GROUP BY 1;
