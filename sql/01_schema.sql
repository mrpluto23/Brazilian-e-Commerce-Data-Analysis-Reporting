-- =====================================================================
-- Olist Brazilian E-Commerce — Database Schema
-- Dialect: PostgreSQL 14+
-- Source dataset: "Brazilian E-Commerce Public Dataset by Olist" (Kaggle)
-- =====================================================================
-- Run order: 01_schema.sql -> 02_load_data.sql -> 03_validation_queries.sql
-- =====================================================================

-- Clean slate (safe to re-run during development)
DROP TABLE IF EXISTS order_reviews        CASCADE;
DROP TABLE IF EXISTS order_payments       CASCADE;
DROP TABLE IF EXISTS order_items          CASCADE;
DROP TABLE IF EXISTS orders               CASCADE;
DROP TABLE IF EXISTS products             CASCADE;
DROP TABLE IF EXISTS product_category_translation CASCADE;
DROP TABLE IF EXISTS sellers              CASCADE;
DROP TABLE IF EXISTS customers            CASCADE;
DROP TABLE IF EXISTS geolocation          CASCADE;


-- ---------------------------------------------------------------------
-- 1. CUSTOMERS
-- One row per customer order-instance. customer_unique_id identifies
-- the *person*; customer_id identifies a single order's customer record
-- (Olist quirk: a repeat buyer gets a new customer_id per order).
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id              VARCHAR(32)  PRIMARY KEY,
    customer_unique_id       VARCHAR(32)  NOT NULL,
    customer_zip_code_prefix VARCHAR(5)   NOT NULL,
    customer_city            VARCHAR(100) NOT NULL,
    customer_state           CHAR(2)      NOT NULL
);
CREATE INDEX idx_customers_unique_id ON customers (customer_unique_id);
CREATE INDEX idx_customers_state     ON customers (customer_state);



-- ---------------------------------------------------------------------
-- 2. GEOLOCATION
-- Many-to-many lat/lng samples per zip prefix. No natural single-column
-- PK (a zip prefix maps to many lat/lng points), so we use a surrogate.
-- ---------------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_id           BIGSERIAL PRIMARY KEY,
    geolocation_zip_code_prefix VARCHAR(5) NOT NULL,
    geolocation_lat          DOUBLE PRECISION,
    geolocation_lng          DOUBLE PRECISION,
    geolocation_city         VARCHAR(100),
    geolocation_state        CHAR(2)
);
CREATE INDEX idx_geo_zip ON geolocation (geolocation_zip_code_prefix);


-- ---------------------------------------------------------------------
-- 3. SELLERS
-- ---------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id              VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5)  NOT NULL,
    seller_city            VARCHAR(100) NOT NULL,
    seller_state           CHAR(2)      NOT NULL
);
CREATE INDEX idx_sellers_state ON sellers (seller_state);

-- ---------------------------------------------------------------------
-- 4. PRODUCT CATEGORY TRANSLATION (category name PT -> EN)
-- ---------------------------------------------------------------------
CREATE TABLE product_category_translation (
    product_category_name          VARCHAR(100) PRIMARY KEY,
    product_category_name_english  VARCHAR(100) NOT NULL
);

-- ---------------------------------------------------------------------
-- 5. PRODUCTS
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id                 VARCHAR(32) PRIMARY KEY,
    product_category_name      VARCHAR(100)
        REFERENCES product_category_translation (product_category_name)
        ON UPDATE CASCADE ON DELETE SET NULL,
    product_name_length        INT,
    product_description_length INT,
    product_photos_qty         INT,
    product_weight_g           NUMERIC(10,2),
    product_length_cm          NUMERIC(10,2),
    product_height_cm          NUMERIC(10,2),
    product_width_cm           NUMERIC(10,2)
);
CREATE INDEX idx_products_category ON products (product_category_name);

-- ---------------------------------------------------------------------
-- 6. ORDERS
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id                       VARCHAR(32) PRIMARY KEY,
    customer_id                    VARCHAR(32) NOT NULL
        REFERENCES customers (customer_id) ON UPDATE CASCADE,
    order_status                   VARCHAR(20) NOT NULL,
    order_purchase_timestamp       TIMESTAMP   NOT NULL,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP
);
CREATE INDEX idx_orders_customer ON orders (customer_id);
CREATE INDEX idx_orders_purchase_ts ON orders (order_purchase_timestamp);
CREATE INDEX idx_orders_status ON orders (order_status);

-- ---------------------------------------------------------------------
-- 7. ORDER ITEMS  (composite PK: order_id + order_item_id)
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_id            VARCHAR(32) NOT NULL
        REFERENCES orders (order_id) ON DELETE CASCADE,
    order_item_id        INT         NOT NULL,
    product_id           VARCHAR(32) NOT NULL
        REFERENCES products (product_id),
    seller_id             VARCHAR(32) NOT NULL
        REFERENCES sellers (seller_id),
    shipping_limit_date    TIMESTAMP,
    price                  NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freight_value          NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),
    PRIMARY KEY (order_id, order_item_id)
);
CREATE INDEX idx_order_items_product ON order_items (product_id);
CREATE INDEX idx_order_items_seller  ON order_items (seller_id);

-- ---------------------------------------------------------------------
-- 8. ORDER PAYMENTS (composite PK: order_id + payment_sequential)
-- One order can have multiple payment installments/methods.
-- ---------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id              VARCHAR(32) NOT NULL
        REFERENCES orders (order_id) ON DELETE CASCADE,
    payment_sequential    INT         NOT NULL,
    payment_type          VARCHAR(20) NOT NULL,
    payment_installments  INT         NOT NULL DEFAULT 1,
    payment_value         NUMERIC(10,2) NOT NULL CHECK (payment_value >= 0),
    PRIMARY KEY (order_id, payment_sequential)
);
CREATE INDEX idx_payments_type ON order_payments (payment_type);

-- ---------------------------------------------------------------------
-- 9. ORDER REVIEWS
-- ---------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id               VARCHAR(32) PRIMARY KEY,
    order_id                VARCHAR(32) NOT NULL
        REFERENCES orders (order_id) ON DELETE CASCADE,
    review_score             SMALLINT NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title     VARCHAR(255),
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);
CREATE INDEX idx_reviews_order ON order_reviews (order_id);
CREATE INDEX idx_reviews_score ON order_reviews (review_score);