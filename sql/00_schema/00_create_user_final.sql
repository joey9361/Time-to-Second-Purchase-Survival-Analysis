------------------------------------------------------------
-- File: sql/00_schema/00_create_user_final.sql
-- Purpose: Create typed final user-input tables for serving
-- Split by grain: order-level and item-level
------------------------------------------------------------

BEGIN;

DROP TABLE IF EXISTS final_user_payments CASCADE;
DROP TABLE IF EXISTS final_user_order_items CASCADE;
DROP TABLE IF EXISTS final_user_orders CASCADE;

-- One row per order submission
CREATE TABLE final_user_orders(
    -- request + order identity
    request_id VARCHAR(50) PRIMARY KEY,
    order_id VARCHAR(50) NOT NULL UNIQUE,

    -- customer raw fields
    customer_id VARCHAR(50) NOT NULL,
    customer_unique_id VARCHAR(50) NOT NULL,
    customer_zip INTEGER NOT NULL,
    customer_city VARCHAR(50) NOT NULL,
    customer_state VARCHAR(3) NOT NULL,

    -- order raw fields
    order_status VARCHAR(25) NOT NULL,
    purchase_date DATE NOT NULL
);

-- One row per item in an order submission
CREATE TABLE final_user_order_items(
    -- join keys
    request_id VARCHAR(50) NOT NULL,
    order_id VARCHAR(50) NOT NULL,
    item_id INTEGER NOT NULL,

    -- item-level raw fields
    product_id VARCHAR(50) NOT NULL,
    seller_id VARCHAR(50) NOT NULL,
    shipping_limit_date DATE NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    freight_value NUMERIC(10,2) NOT NULL,

    -- product raw fields (only columns needed for downstream feature engineering)
    product_category_name TEXT NOT NULL,

    -- seller raw fields
    seller_zip INTEGER NOT NULL,
    seller_city VARCHAR(50) NOT NULL,
    seller_state VARCHAR(3) NOT NULL,

    PRIMARY KEY(request_id, item_id),
    FOREIGN KEY (request_id) REFERENCES final_user_orders(request_id),
    FOREIGN KEY (order_id) REFERENCES final_user_orders(order_id)
);

-- One row per payment sequence in an order submission
CREATE TABLE final_user_payments(
    request_id VARCHAR(50) NOT NULL,
    order_id VARCHAR(50) NOT NULL,
    payment_sequential INTEGER NOT NULL,
    payment_type VARCHAR(25) NOT NULL,
    num_installments INTEGER NOT NULL,
    payment_value NUMERIC(10,2) NOT NULL,

    PRIMARY KEY(request_id, payment_sequential),
    FOREIGN KEY (request_id) REFERENCES final_user_orders(request_id),
    FOREIGN KEY (order_id) REFERENCES final_user_orders(order_id)
);

COMMIT;