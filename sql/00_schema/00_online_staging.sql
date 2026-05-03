---------------------------------------------------------
-- File: sql/00_schema/00_create_staging_users.sql
-- Purpose: Create staging table for raw prediction input
-- All columns are TEXT to prevent ingestion failures
---------------------------------------------------------

-- One row per order submission (order/customer/payment-level fields)
CREATE TABLE IF NOT EXISTS staging_user_orders(
    -- request + order identity
    request_id TEXT,
    order_id TEXT,

    -- customer raw fields
    customer_id TEXT,
    customer_unique_id TEXT,
    customer_zip TEXT,
    customer_city TEXT,
    customer_state TEXT,

    -- order raw fields
    order_status TEXT,
    purchase_date TEXT,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per item in an order (item/product/seller-level fields)
CREATE TABLE IF NOT EXISTS staging_user_order_items(
    -- join keys
    request_id TEXT,
    order_id TEXT,
    item_id TEXT,

    -- item-level raw fields from form payload
    product_id TEXT,
    seller_id TEXT,
    shipping_limit_date TEXT,
    price TEXT,
    freight_value TEXT,

    -- product raw fields
    product_category_name TEXT,

    -- seller raw fields
    seller_zip TEXT,
    seller_city TEXT,
    seller_state TEXT,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per payment sequence in an order
CREATE TABLE IF NOT EXISTS staging_user_payments(
    -- join keys
    request_id TEXT,
    order_id TEXT,
    payment_sequential TEXT,

    -- payment raw fields
    payment_type TEXT,
    num_installments TEXT,
    payment_value TEXT,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for maintenence cleanup queries
CREATE INDEX IF NOT EXISTS idx_staging_user_orders_ingested_at ON staging_user_orders (ingested_at);
CREATE INDEX IF NOT EXISTS idx_staging_user_order_items_ingested_at ON staging_user_order_items (ingested_at);
CREATE INDEX IF NOT EXISTS idx_staging_user_payments_ingested_at ON staging_user_payments (ingested_at);