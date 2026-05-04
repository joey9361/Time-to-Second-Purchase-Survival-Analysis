------------------------------------------------------------
-- File: sql/00_schema/00_create_user_final.sql
-- Purpose: Create typed final user-input tables for serving
-- Split by grain: order-level and item-level
------------------------------------------------------------

-- One row per order submission
CREATE TABLE IF NOT EXISTS final_user_orders(
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
    purchase_date DATE NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per item in an order submission
CREATE TABLE IF NOT EXISTS final_user_order_items(
    -- join keys
    request_id VARCHAR(50),
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

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY(request_id, item_id),
    FOREIGN KEY (request_id) REFERENCES final_user_orders(request_id),
    FOREIGN KEY (order_id) REFERENCES final_user_orders(order_id)
);

-- One row per payment sequence in an order submission
CREATE TABLE IF NOT EXISTS final_user_payments(
    request_id VARCHAR(50),
    order_id VARCHAR(50) NOT NULL,
    payment_sequential INTEGER NOT NULL,
    payment_type VARCHAR(25) NOT NULL,
    num_installments INTEGER NOT NULL,
    payment_value NUMERIC(10,2) NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY(request_id, payment_sequential),
    FOREIGN KEY (request_id) REFERENCES final_user_orders(request_id),
    FOREIGN KEY (order_id) REFERENCES final_user_orders(order_id)
);

CREATE TABLE IF NOT EXISTS users_feature_engineering(
    request_id VARCHAR(50) PRIMARY KEY,
    order_id VARCHAR(50) UNIQUE NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    order_status TEXT NOT NULL,
    t_pred_date DATE NOT NULL,
    purchase_date DATE NOT NULL,
    customer_unique_id VARCHAR(50) NOT NULL,
    customer_zip INTEGER NOT NULL,
    purchase_month INTEGER NOT NULL,
    purchase_day_of_week INTEGER NOT NULL,
    purchased_on_weekend INTEGER NOT NULL,
    most_freq_payment_type_encoded INTEGER NOT NULL,
    payment_type_count INTEGER NOT NULL,
    total_installments INTEGER NOT NULL,
    total_payment_value NUMERIC(10, 2) NOT NULL,
    num_items_in_order INTEGER NOT NULL,
    total_freight_value NUMERIC(10, 2) NOT NULL, 
    total_merch_value NUMERIC(10, 2) NOT NULL,
    total_order_value NUMERIC(10, 2) NOT NULL,
    avg_price NUMERIC(10, 2) NOT NULL,
    price_std NUMERIC(10, 2) NOT NULL,
    min_price NUMERIC(10, 2) NOT NULL,
    price_range NUMERIC(10, 2) NOT NULL,
    freight_price_ratio FLOAT NOT NULL,
    max_freight_ratio FLOAT NOT NULL,
    min_freight_ratio FLOAT NOT NULL,
    has_multiple_seller_states INTEGER NOT NULL,
    num_seller_states INTEGER NOT NULL,
    latest_shipping_limit_date DATE NOT NULL,
    shipping_window_days INTEGER NOT NULL,
    most_exp_product_id VARCHAR(50) NOT NULL,
    most_exp_price NUMERIC(10, 2) NOT NULL,
    most_exp_freight NUMERIC(10, 2) NOT NULL,
    most_exp_prod_category TEXT NOT NULL,
    most_exp_encoded_category INTEGER NOT NULL,
    most_freq_category TEXT NOT NULL,
    most_freq_encoded_category INTEGER NOT NULL,
    num_distinct_categories INTEGER NOT NULL,
    most_freq_cat_concentration FLOAT NOT NULL,
    val_seller_id VARCHAR(50) NOT NULL,
    val_seller_zip INTEGER NOT NULL,
    val_seller_city VARCHAR(50) NOT NULL,
    val_seller_state VARCHAR(3) NOT NULL,
    val_seller_encoded_state INTEGER NOT NULL,
    has_duplicate_sellers INTEGER NOT NULL,
    has_multiple_sellers INTEGER NOT NULL,
    num_distinct_sellers INTEGER NOT NULL,
    avg_seller_price NUMERIC(10, 2) NOT NULL,
    avg_seller_freight NUMERIC(10, 2) NOT NULL,
    seller_order_volume INTEGER NOT NULL,
    seller_item_volume INTEGER NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_final_user_orders_ingested_at ON final_user_orders (ingested_at);
CREATE INDEX IF NOT EXISTS idx_final_user_order_items_ingested_at ON final_user_order_items (ingested_at);
CREATE INDEX IF NOT EXISTS idx_final_user_payments_ingested_at ON final_user_payments (ingested_at);
CREATE INDEX IF NOT EXISTS idx_users_feature_engineering_ingested_at ON users_feature_engineering (ingested_at);
