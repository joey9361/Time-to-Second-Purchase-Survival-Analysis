-----------------------------------------------------
-- File: sql/00_schema/00_create_finals_tables.sql
-- Purpose: Create finals tables for each csv dataset
-- Include the correct data types for each column
-- Staging tables will be transformed and loaded in
-----------------------------------------------------

BEGIN;

DROP TABLE IF EXISTS final_orders CASCADE;
DROP TABLE IF EXISTS final_sellers CASCADE;
DROP TABLE IF EXISTS final_product_category CASCADE;
DROP TABLE IF EXISTS final_products CASCADE;
DROP TABLE IF EXISTS final_item_orders CASCADE;
DROP TABLE IF EXISTS final_customers CASCADE;
DROP TABLE IF EXISTS final_payments CASCADE;
DROP TABLE IF EXISTS final_reviews CASCADE;

-- Orders table - Children: final_customers, final_item_orders, final_payments, final_reviews
CREATE TABLE final_orders(
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL UNIQUE,
    order_status VARCHAR(25),
    purchase_date DATE NOT NULL,
    order_approval_date DATE,
    delivered_carrier_date DATE,
    delivered_customer_date DATE,
    estimated_delivery_date DATE
);

-- Sellers table - Children: final_item_orders
CREATE TABLE final_sellers(
    seller_id VARCHAR(50) PRIMARY KEY,
    zip_code INTEGER, 
    seller_city VARCHAR(50),
    seller_state VARCHAR(3)
);

-- Products_category table - Children: final_products
CREATE TABLE final_product_category(
    product_category TEXT PRIMARY KEY,
    product_category_english TEXT
);

-- Products table - Parent: final_product_category / Children: final_item_orders  
CREATE TABLE final_products(
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name TEXT NOT NULL,
    product_name_length INTEGER,
    product_description_length INTEGER,
    product_photos_qty INTEGER,
    product_weight_g INTEGER,
    product_length_cm INTEGER,
    product_height_cm INTEGER,
    product_width_cm INTEGER,
    FOREIGN KEY(product_category_name) REFERENCES final_product_category(product_category)
); 

-- Item_orders table - Parents: final_orders, final_sellers, final_products
CREATE TABLE final_item_orders(
    order_id VARCHAR(50),
    item_id INTEGER,
    product_id VARCHAR(50) NOT NULL,
    seller_id VARCHAR(50) NOT NULL,
    shipping_limit_date DATE NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    freight_value NUMERIC(10,2), 
    PRIMARY KEY(order_id, item_id),
    FOREIGN KEY(order_id) REFERENCES final_orders(order_id),
    FOREIGN KEY(product_id) REFERENCES final_products(product_id),
    FOREIGN KEY(seller_id) REFERENCES final_sellers(seller_id)
);

-- Customers table - Parents: final_orders
CREATE TABLE final_customers(
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50) NOT NULL,
    zip_code INTEGER,
    city VARCHAR(50),
    customer_state VARCHAR(3),
    FOREIGN KEY (customer_id) REFERENCES final_orders(customer_id)
);

-- Payments table - Parents: final_orders
CREATE TABLE final_payments(
    order_id VARCHAR(50),
    payment_sequential INTEGER,
    payment_type VARCHAR(25),
    num_installments INTEGER,
    payment_value NUMERIC(10,2) NOT NULL,
    PRIMARY KEY(order_id, payment_sequential),
    FOREIGN KEY(order_id) REFERENCES final_orders(order_id)
);

-- Reviews table - Parent: final_orders
CREATE TABLE final_reviews(
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score INTEGER NOT NULL,
    comment_title TEXT,
    comment_message TEXT,
    post_date DATE NOT NULL,
    answer_date DATE, -- Only need to know it exists, value is not relevant
    PRIMARY KEY(review_id, order_id),
    FOREIGN KEY(order_id) REFERENCES final_orders(order_id)
);

COMMIT;

