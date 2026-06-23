-- =====================================================================
-- 03_validation_queries.sql
-- Run immediately after loading data to confirm the import succeeded
-- and the relational integrity holds.
-- =====================================================================

-- 1. Row counts per table — compare against known Olist dataset sizes
--    (customers ~99,441 | orders ~99,441 | order_items ~112,650 |
--     order_payments ~103,886 | order_reviews ~99,224 | products ~32,951 |
--     sellers ~3,095 | geolocation ~1,000,163 | category_translation 71)
SELECT 'customers'        AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders',                 COUNT(*) FROM orders
UNION ALL SELECT 'order_items',            COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments',         COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',          COUNT(*) FROM order_reviews
UNION ALL SELECT 'products',               COUNT(*) FROM products
UNION ALL SELECT 'sellers',                COUNT(*) FROM sellers
UNION ALL SELECT 'geolocation',            COUNT(*) FROM geolocation
UNION ALL SELECT 'product_category_translation', COUNT(*) FROM product_category_translation
ORDER BY table_name;

-- 2. Orphan check: order_items pointing to non-existent orders
SELECT COUNT(*) AS orphan_order_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- 3. Orphan check: orders pointing to non-existent customers
SELECT COUNT(*) AS orphan_orders
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- 4. Null / blank checks on critical columns
SELECT
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_ts,
    SUM(CASE WHEN order_status IS NULL OR order_status = '' THEN 1 ELSE 0 END) AS null_status
FROM orders;

-- 5. Duplicate primary key check (should always return 0 rows)
SELECT order_id, order_item_id, COUNT(*)
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- 6. Review score domain check (should be empty: CHECK constraint should
--    already prevent this, but confirms post-load state)
SELECT review_score, COUNT(*)
FROM order_reviews
WHERE review_score NOT BETWEEN 1 AND 5
GROUP BY review_score;

-- 7. Date sanity check: delivered date should not precede purchase date
SELECT COUNT(*) AS impossible_delivery_dates
FROM orders
WHERE order_delivered_customer_date < order_purchase_timestamp;

-- 8. Category coverage: % of products with a category mapped to English
SELECT
    ROUND(100.0 * COUNT(t.product_category_name_english) / COUNT(*), 2) AS pct_mapped
FROM products p
LEFT JOIN product_category_translation t
    ON p.product_category_name = t.product_category_name;