-- =====================================================================
-- 02_load_data.sql
-- Loads the 9 raw Olist CSVs (downloaded from Kaggle into data/raw/)
-- into the schema created by 01_schema.sql.

--   psql -d olist_db -f sql/02_load_data.sql
--   this pure sql file does the same job as data_loader.py


-- =====================================================================



-- 1. Lookup / independent tables first
\copy product_category_translation (product_category_name, product_category_name_english) \
    FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true);

\copy customers (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state) \
    FROM 'data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true);

\copy sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state) \
    FROM 'data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true);

\copy geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state) \
    FROM 'data/raw/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true);

-- 2. Products depend on category translation
\copy products (product_id, product_category_name, product_name_length, product_description_length, \
                product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm) \
    FROM 'data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true);

-- 3. Orders depend on customers
\copy orders (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, \
              order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date) \
    FROM 'data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true);

-- 4. Order items depend on orders, products, sellers
\copy order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value) \
    FROM 'data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true);

-- 5. Payments and reviews depend on orders
\copy order_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value) \
    FROM 'data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true);

\copy order_reviews (review_id, order_id, review_score, review_comment_title, review_comment_message, \
                      review_creation_date, review_answer_timestamp) \
    FROM 'data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true);

-- =====================================================================
-- Post-load cleanup / data quality fixes
-- =====================================================================

-- The reviews CSV occasionally has duplicate review_id rows for the
-- same order (multiplicate review answers) — drop exact duplicates.
DELETE FROM order_reviews a
USING order_reviews b
WHERE a.ctid < b.ctid
  AND a.review_id = b.review_id;

-- product_category_name is sometimes NULL/blank in the raw file —
-- normalize blank strings to NULL so the FK and category queries behave.
UPDATE products SET product_category_name = NULL
WHERE product_category_name = '';

-- Defensive: remove any order_items rows that reference a product/seller
-- not present in their parent tables (rare encoding issues in raw CSV).
DELETE FROM order_items oi
WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = oi.product_id)
   OR NOT EXISTS (SELECT 1 FROM sellers  s WHERE s.seller_id  = oi.seller_id);

ANALYZE customers;
ANALYZE orders;
ANALYZE order_items;
ANALYZE order_payments;
ANALYZE order_reviews;
ANALYZE products;
ANALYZE sellers;
ANALYZE geolocation;
ANALYZE product_category_translation;
