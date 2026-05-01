---------------------------------------------------------
-- File: sql/01_schema/01_create_staging.sql
-- Purpose: Create all staging tables for raw CSV data
-- All columns are TEXT to prevent COPY errors
-- Tables are dropped with CASCADE to handle dependencies
---------------------------------------------------------

BEGIN;
-- Customers dataset
DROP TABLE IF EXISTS staging_customers CASCADE;

CREATE TABLE staging_customers(
    customer_id TEXT,
    customer_unique_id TEXT,
    zip_code TEXT,
    city TEXT,
    customer_state TEXT
);

-- Location dataset
DROP TABLE IF EXISTS staging_location CASCADE;

CREATE TABLE staging_location(
    zip_code TEXT,
    latitude TEXT, 
    longitude TEXT,
    city TEXT, 
    location_state TEXT
);

-- Order items dataset
DROP TABLE IF EXISTS staging_item_orders CASCADE;

CREATE TABLE staging_item_orders(
    order_id TEXT,
    item_id TEXT,
    product_id TEXT,
    seller_id TEXT,
    shipping_limit_date TEXT,
    price TEXT,
    freight_value TEXT
);

-- Payments dataset
DROP TABLE IF EXISTS staging_payments CASCADE;

CREATE TABLE staging_payments(
    order_id TEXT,
    payment_sequential TEXT,
    payment_type TEXT,
    num_installments TEXT,
    payment_value TEXT
);

-- Reviews Dataset
DROP TABLE IF EXISTS staging_reviews CASCADE;

CREATE TABLE staging_reviews(
    review_id TEXT,
    order_id TEXT,
    review_score TEXT,
    comment_title TEXT,
    comment_message TEXT,
    post_date TEXT,
    answer_date TEXT
);

-- Orders dataset
DROP TABLE IF EXISTS staging_orders CASCADE;

CREATE TABLE staging_orders(
    order_id TEXT,
    customer_id TEXT,
    order_status TEXT,
    purchase_date TEXT,
    order_approval_date TEXT,
    delivered_carrier_date TEXT,
    delivered_customer_date TEXT,
    estimated_delivery_date TEXT
);

-- Product category dataset
DROP TABLE IF EXISTS staging_product_category CASCADE;

CREATE TABLE staging_product_category(
    product_category TEXT,
    product_category_english TEXT
);

-- Products Dataset
DROP TABLE IF EXISTS staging_products CASCADE;

CREATE TABLE staging_products(
    product_id TEXT,
    product_category_name TEXT,
    product_name_length TEXT,
    product_description_length TEXT,
    product_photos_qty TEXT,
    product_weight_g TEXT,
    product_length_cm TEXT,
    product_height_cm TEXT,
    product_width_cm TEXT
);

-- Sellers dataset
DROP TABLE IF EXISTS staging_sellers CASCADE;

CREATE TABLE staging_sellers(
    seller_id TEXT,
    zip_code TEXT,
    seller_city TEXT,
    seller_state TEXT
);

COMMIT;