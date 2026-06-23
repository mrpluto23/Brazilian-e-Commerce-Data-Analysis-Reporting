-- =====================================================================
-- 05_advanced_analysis.sql
-- Advanced insights using window functions, CTEs, and multi-step logic.
-- These differentiate the project from a basic GROUP BY exercise.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A1. Month-over-month revenue growth rate (window function: LAG)
-- ---------------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
        SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('unavailable', 'canceled')
    GROUP BY 1
)
SELECT
    order_month,
    ROUND(revenue::NUMERIC, 2) AS revenue,
    ROUND(LAG(revenue) OVER (ORDER BY order_month)::NUMERIC, 2) AS prev_month_revenue,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
        / LAG(revenue) OVER (ORDER BY order_month)
    , 2) AS mom_growth_pct
FROM monthly_revenue
ORDER BY order_month;

-- ---------------------------------------------------------------------
-- A2. Running (cumulative) revenue total — window function: SUM OVER
-- ---------------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
           SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY 1
)
SELECT
    order_month,
    ROUND(revenue::NUMERIC, 2) AS revenue,
    ROUND(SUM(revenue) OVER (ORDER BY order_month)::NUMERIC, 2) AS cumulative_revenue
FROM monthly_revenue
ORDER BY order_month;

-- ---------------------------------------------------------------------
-- A3. Top 3 sellers per state by revenue — window function: RANK
-- ---------------------------------------------------------------------
WITH seller_revenue AS (
    SELECT
        s.seller_state,
        s.seller_id,
        SUM(oi.price) AS revenue,
        RANK() OVER (PARTITION BY s.seller_state ORDER BY SUM(oi.price) DESC) AS state_rank
    FROM order_items oi
    JOIN sellers s ON s.seller_id = oi.seller_id
    GROUP BY s.seller_state, s.seller_id
)
SELECT seller_state, seller_id, ROUND(revenue::NUMERIC, 2) AS revenue, state_rank
FROM seller_revenue
WHERE state_rank <= 3
ORDER BY seller_state, state_rank;

-- ---------------------------------------------------------------------
-- A4. Customer RFM-style segmentation (Recency, Frequency, Monetary)
-- Uses NTILE window function to bucket customers into quartiles.
-- ---------------------------------------------------------------------
WITH customer_metrics AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order_date,
        COUNT(DISTINCT o.order_id)      AS frequency,
        SUM(oi.price)                   AS monetary
    FROM customers c
    JOIN orders o      ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY c.customer_unique_id
),
reference_date AS (
    SELECT MAX(order_purchase_timestamp) AS max_date FROM orders
),
rfm_scored AS (
    SELECT
        cm.customer_unique_id,
        EXTRACT(DAY FROM (rd.max_date - cm.last_order_date))::INT AS recency_days,
        cm.frequency,
        cm.monetary,
        NTILE(4) OVER (ORDER BY EXTRACT(DAY FROM (rd.max_date - cm.last_order_date)) DESC) AS recency_quartile,
        NTILE(4) OVER (ORDER BY cm.frequency)  AS frequency_quartile,
        NTILE(4) OVER (ORDER BY cm.monetary)   AS monetary_quartile
    FROM customer_metrics cm
    CROSS JOIN reference_date rd
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary::NUMERIC, 2) AS monetary,
    recency_quartile, frequency_quartile, monetary_quartile,
    (recency_quartile + frequency_quartile + monetary_quartile) AS rfm_score
FROM rfm_scored
ORDER BY rfm_score DESC
LIMIT 25;

-- ---------------------------------------------------------------------
-- A5. Delivery delay impact on review score (subquery + CASE buckets)
-- ---------------------------------------------------------------------
SELECT
    delay_bucket,
    COUNT(*) AS num_orders,
    ROUND(AVG(review_score)::NUMERIC, 2) AS avg_review_score
FROM (
    SELECT
        r.review_score,
        CASE
            WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'on_time_or_early'
            WHEN o.order_delivered_customer_date - o.order_estimated_delivery_date <= INTERVAL '3 days' THEN 'late_1_3_days'
            ELSE 'late_4plus_days'
        END AS delay_bucket
    FROM orders o
    JOIN order_reviews r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
) bucketed
GROUP BY delay_bucket
ORDER BY avg_review_score;

-- ---------------------------------------------------------------------
-- A6. Product categories with above-average price but below-average
--     review score — flags potential "overpriced/underdelivering" SKUs
--     (subquery in WHERE clause)
-- ---------------------------------------------------------------------
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name) AS category,
    ROUND(AVG(oi.price)::NUMERIC, 2)         AS avg_price,
    ROUND(AVG(r.review_score)::NUMERIC, 2)   AS avg_review_score,
    COUNT(*) AS items_sold
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN product_category_translation t ON t.product_category_name = p.product_category_name
JOIN order_reviews r ON r.order_id = oi.order_id
GROUP BY category
HAVING AVG(oi.price) > (SELECT AVG(price) FROM order_items)
   AND AVG(r.review_score) < (SELECT AVG(review_score) FROM order_reviews)
ORDER BY avg_price DESC;

-- ---------------------------------------------------------------------
-- A7. Cohort-style first-purchase-month revenue tracking
-- (groups customers by their acquisition month, tracks total spend)
-- ---------------------------------------------------------------------
WITH first_purchase AS (
    SELECT customer_unique_id, MIN(order_purchase_timestamp) AS first_order_ts
    FROM customers c
    JOIN orders o ON o.customer_id = c.customer_id
    GROUP BY customer_unique_id
)
SELECT
    DATE_TRUNC('month', fp.first_order_ts)::DATE AS acquisition_month,
    COUNT(DISTINCT fp.customer_unique_id)        AS new_customers,
    ROUND(SUM(oi.price)::NUMERIC, 2)             AS total_revenue_from_cohort
FROM first_purchase fp
JOIN customers c   ON c.customer_unique_id = fp.customer_unique_id
JOIN orders o      ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY 1
ORDER BY 1;