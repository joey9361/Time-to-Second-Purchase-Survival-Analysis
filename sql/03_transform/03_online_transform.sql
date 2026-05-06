------------------------------------------------------------------------------
-- File: sql/03_transform/users.sql
-- Purpose: Transform one online user request from staging -> final tables
-- Usage: pass request_id as a SQL parameter (:request_id)
------------------------------------------------------------------------------

-- ------------------------
-- Rejection/audit tables
-- ------------------------
CREATE TABLE IF NOT EXISTS rejected_user_orders (
    request_id TEXT,
    order_id TEXT,
    customer_id TEXT,
    customer_unique_id TEXT,
    customer_zip TEXT,
    customer_city TEXT,
    customer_state TEXT,
    order_status TEXT,
    purchase_date TEXT,
    rejected_reason TEXT,
    rejected_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rejected_user_payments (
    request_id TEXT,
    order_id TEXT,
    payment_sequential TEXT,
    payment_type TEXT,
    num_installments TEXT,
    payment_value TEXT,
    rejected_reason TEXT,
    rejected_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rejected_user_order_items (
    request_id TEXT,
    order_id TEXT,
    item_id TEXT,
    product_id TEXT,
    seller_id TEXT,
    shipping_limit_date TEXT,
    price TEXT,
    freight_value TEXT,
    product_category_name TEXT,
    seller_zip TEXT,
    seller_city TEXT,
    seller_state TEXT,
    rejected_reason TEXT,
    rejected_at TIMESTAMP DEFAULT NOW()
);

-- --------------------------------------
-- Transform order/customer rows
-- --------------------------------------
WITH scoped_orders AS (
    SELECT *
    FROM staging_user_orders
    WHERE request_id = :request_id
),
processed_orders AS (
    SELECT
        -- CASE WHEN request_id::VARCHAR(50) = '' THEN NULL
        -- ELSE request_id::VARCHAR(50) END AS request_id,
        -- CASE WHEN order_id::VARCHAR(50) = '' THEN NULL
        -- ELSE order_id::VARCHAR(50) END AS order_id,
        request_id::VARCHAR(50) AS request_id,
        order_id::VARCHAR(50) AS order_id,
        customer_id::VARCHAR(50) AS customer_id,
        customer_unique_id::VARCHAR(50) AS customer_unique_id,
        CASE WHEN customer_zip ~ '^[0-9]+$' THEN customer_zip::INTEGER ELSE NULL END AS customer_zip,
        customer_city::VARCHAR(50) AS customer_city,
        customer_state::VARCHAR(3) AS customer_state,
        COALESCE(order_status::VARCHAR(25), 'created') AS order_status,
        CASE
            WHEN purchase_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN purchase_date::DATE
            WHEN purchase_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
                THEN purchase_date::TIMESTAMP::DATE
            ELSE NULL
        END AS purchase_date,
        ingested_at
    FROM scoped_orders
),
valid_orders AS (
    -- Staging allows duplicate request_id rows (retries / double inserts). ON CONFLICT must see each key once.
    SELECT DISTINCT ON (request_id)
        *
    FROM processed_orders
    WHERE request_id IS NOT NULL
      AND order_id IS NOT NULL
      AND customer_id IS NOT NULL
      AND customer_unique_id IS NOT NULL
      AND customer_zip IS NOT NULL
      AND customer_city IS NOT NULL
      AND customer_state IS NOT NULL
      AND purchase_date IS NOT NULL
    ORDER BY request_id, ingested_at DESC NULLS LAST
),
invalid_orders AS (
    SELECT
        s.*,
        CASE
            -- WHEN s.request_id = '' THEN 'Empty request_id in table staging_user_orders'
            WHEN s.request_id IS NULL THEN 'NULL request_id in table staging_user_orders'
            -- WHEN s.order_id = '' THEN 'Empty order_id in table staging_user_orders'
            WHEN s.order_id IS NULL THEN 'NULL order_id in table staging_user_orders'
            WHEN s.customer_id IS NULL THEN 'NULL customer_id in table staging_user_orders'
            WHEN s.customer_unique_id IS NULL THEN 'NULL customer_unique_id in table staging_user_orders'
            WHEN s.customer_zip IS NULL OR s.customer_zip !~ '^[0-9]+$' THEN 'Invalid customer_zip in table staging_user_orders'
            WHEN s.customer_city IS NULL THEN 'NULL customer_city in table staging_user_orders'
            WHEN s.customer_state IS NULL THEN 'NULL customer_state in table staging_user_orders'
            WHEN s.purchase_date IS NULL OR (
                s.purchase_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                AND s.purchase_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            ) THEN 'Invalid purchase_date in table staging_user_orders'
            ELSE 'Unknown validation error in table staging_user_orders'
        END AS rejected_reason
    FROM scoped_orders s
    LEFT JOIN valid_orders v ON s.request_id = v.request_id
    WHERE v.request_id IS NULL
),
inserted_orders AS (
    INSERT INTO final_user_orders (
        request_id,
        order_id,
        customer_id,
        customer_unique_id,
        customer_zip,
        customer_city,
        customer_state,
        order_status,
        purchase_date,
        ingested_at
    )
    SELECT
        request_id,
        order_id,
        customer_id,
        customer_unique_id,
        customer_zip,
        customer_city,
        customer_state,
        order_status,
        purchase_date,
        ingested_at
    FROM valid_orders
    ON CONFLICT (request_id) DO UPDATE SET
        order_id = EXCLUDED.order_id,
        customer_id = EXCLUDED.customer_id,
        customer_unique_id = EXCLUDED.customer_unique_id,
        customer_zip = EXCLUDED.customer_zip,
        customer_city = EXCLUDED.customer_city,
        customer_state = EXCLUDED.customer_state,
        order_status = EXCLUDED.order_status,
        purchase_date = EXCLUDED.purchase_date,
        ingested_at = EXCLUDED.ingested_at
    RETURNING request_id
)
INSERT INTO rejected_user_orders (
    request_id, order_id, customer_id, customer_unique_id, customer_zip,
    customer_city, customer_state, order_status, purchase_date, rejected_reason
)
SELECT
    request_id, order_id, customer_id, customer_unique_id, customer_zip,
    customer_city, customer_state, order_status, purchase_date, rejected_reason
FROM invalid_orders;

-- ----------------------------
-- Transform payment-level rows
-- ----------------------------
WITH scoped_payments AS (
    SELECT *
    FROM staging_user_payments
    WHERE request_id = :request_id
),
processed_payments AS (
    SELECT
        request_id::VARCHAR(50) AS request_id,
        order_id::VARCHAR(50) AS order_id,
        CASE WHEN payment_sequential ~ '^[0-9]+$' THEN payment_sequential::INTEGER ELSE NULL END AS payment_sequential,
        COALESCE(payment_type::VARCHAR(25), 'credit_card') AS payment_type,
        CASE WHEN num_installments ~ '^[0-9]+$' THEN num_installments::INTEGER ELSE NULL END AS num_installments,
        CASE WHEN TRIM(payment_value) ~ '^[0-9]+(\.[0-9]+)?$' THEN TRIM(payment_value)::NUMERIC(10,2) ELSE NULL END AS payment_value,
        ingested_at
    FROM scoped_payments
),
valid_payments AS (
    SELECT DISTINCT ON (p.request_id, p.payment_sequential)
        p.*
    FROM processed_payments p
    INNER JOIN final_user_orders o ON p.request_id = o.request_id AND p.order_id = o.order_id
    WHERE p.request_id IS NOT NULL
      AND p.order_id IS NOT NULL
      AND p.payment_sequential IS NOT NULL
      AND p.payment_type IS NOT NULL
      AND p.num_installments IS NOT NULL
      AND p.payment_value IS NOT NULL
    ORDER BY p.request_id, p.payment_sequential, p.ingested_at DESC NULLS LAST
),
invalid_payments AS (
    SELECT
        s.*,
        CASE
            WHEN s.request_id = '' THEN 'Empty request_id in table staging_user_payments'
            WHEN s.order_id = '' THEN 'Empty order_id in table staging_user_payments'
            WHEN s.request_id IS NULL THEN format(
                'NULL request_id in table staging_user_payments, payment_sequential %s',
                COALESCE(s.payment_sequential::text, 'NULL')
            )
            WHEN s.order_id IS NULL THEN format(
                'NULL order_id in table staging_user_payments, payment_sequential %s',
                COALESCE(s.payment_sequential::text, 'NULL')
            )
            WHEN s.payment_sequential IS NULL OR s.payment_sequential !~ '^[0-9]+$' THEN format(
                'Invalid payment_sequential in table staging_user_payments, payment_sequential %s',
                COALESCE(s.payment_sequential::text, 'NULL')
            )
            WHEN s.num_installments IS NULL OR s.num_installments !~ '^[0-9]+$' THEN format(
                'Invalid num_installments in table staging_user_payments, payment_sequential %s',
                COALESCE(s.payment_sequential::text, 'NULL')
            )
            WHEN s.payment_value IS NULL OR TRIM(s.payment_value) !~ '^[0-9]+(\.[0-9]+)?$' THEN format(
                'Invalid payment_value in table staging_user_payments, payment_sequential %s',
                COALESCE(s.payment_sequential::text, 'NULL')
            )
            ELSE format(
                'Unknown validation error in table staging_user_payments, payment_sequential %s',
                COALESCE(s.payment_sequential::text, 'NULL')
            )
        END AS rejected_reason
    FROM scoped_payments s
    LEFT JOIN valid_payments v
        ON s.request_id = v.request_id
       AND s.order_id = v.order_id
       AND (CASE WHEN s.payment_sequential ~ '^[0-9]+$' THEN s.payment_sequential::INTEGER ELSE NULL END) = v.payment_sequential
    WHERE v.request_id IS NULL
),
inserted_payments AS (
    INSERT INTO final_user_payments (
        request_id,
        order_id,
        payment_sequential,
        payment_type,
        num_installments,
        payment_value,
        ingested_at
    )
    SELECT
        request_id,
        order_id,
        payment_sequential,
        payment_type,
        num_installments,
        payment_value,
        ingested_at
    FROM valid_payments
    ON CONFLICT (request_id, payment_sequential) DO UPDATE SET
        order_id = EXCLUDED.order_id,
        payment_type = EXCLUDED.payment_type,
        num_installments = EXCLUDED.num_installments,
        payment_value = EXCLUDED.payment_value,
        ingested_at = EXCLUDED.ingested_at
    RETURNING request_id, payment_sequential
)
INSERT INTO rejected_user_payments (
    request_id, order_id, payment_sequential, payment_type, num_installments, payment_value, rejected_reason
)
SELECT
    request_id, order_id, payment_sequential, payment_type, num_installments, payment_value, rejected_reason
FROM invalid_payments;

-- ----------------------------
-- Transform item-level rows
-- ----------------------------
WITH scoped_items AS (
    SELECT *
    FROM staging_user_order_items
    WHERE request_id = :request_id
),
processed_items AS (
    SELECT
        request_id::VARCHAR(50) AS request_id,
        order_id::VARCHAR(50) AS order_id,
        CASE WHEN item_id ~ '^[0-9]+$' THEN item_id::INTEGER ELSE NULL END AS item_id,
        product_id::VARCHAR(50) AS product_id,
        seller_id::VARCHAR(50) AS seller_id,
        CASE
            WHEN shipping_limit_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN shipping_limit_date::DATE
            WHEN shipping_limit_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
                THEN shipping_limit_date::TIMESTAMP::DATE
            ELSE NULL
        END AS shipping_limit_date,
        CASE WHEN TRIM(price) ~ '^[0-9]+(\.[0-9]+)?$' THEN TRIM(price)::NUMERIC(10,2) ELSE NULL END AS price,
        CASE WHEN TRIM(freight_value) ~ '^[0-9]+(\.[0-9]+)?$' THEN TRIM(freight_value)::NUMERIC(10,2) ELSE NULL END AS freight_value,
        COALESCE(product_category_name, 'unknown')::TEXT AS product_category_name,
        CASE WHEN seller_zip ~ '^[0-9]+$' THEN seller_zip::INTEGER ELSE NULL END AS seller_zip,
        seller_city::VARCHAR(50) AS seller_city,
        seller_state::VARCHAR(3) AS seller_state,
        ingested_at
    FROM scoped_items
),
valid_items AS (
    SELECT DISTINCT ON (p.request_id, p.item_id)
        p.*
    FROM processed_items p
    INNER JOIN final_user_orders o ON p.request_id = o.request_id AND p.order_id = o.order_id
    WHERE p.request_id IS NOT NULL
      AND p.order_id IS NOT NULL
      AND p.item_id IS NOT NULL
      AND p.product_id IS NOT NULL
      AND p.seller_id IS NOT NULL
      AND p.shipping_limit_date IS NOT NULL
      AND p.price IS NOT NULL
      AND p.freight_value IS NOT NULL
      AND p.product_category_name IS NOT NULL
      AND p.seller_zip IS NOT NULL
      AND p.seller_city IS NOT NULL
      AND p.seller_state IS NOT NULL
    ORDER BY p.request_id, p.item_id, p.ingested_at DESC NULLS LAST
),
invalid_items AS (
    SELECT
        s.*,
        CASE
            WHEN s.request_id = '' THEN 'Empty request_id in table staging_user_order_items'
            WHEN s.order_id = '' THEN 'Empty order_id in table staging_user_order_items'
            WHEN s.request_id IS NULL THEN format(
                'NULL request_id in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.order_id IS NULL THEN format(
                'NULL order_id in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.item_id IS NULL OR s.item_id !~ '^[0-9]+$' THEN format(
                'Invalid item_id in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.product_id IS NULL THEN format(
                'NULL product_id in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.seller_id IS NULL THEN format(
                'NULL seller_id in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.shipping_limit_date IS NULL OR (
                s.shipping_limit_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                AND s.shipping_limit_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            ) THEN format(
                'Invalid shipping_limit_date in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.price IS NULL OR TRIM(s.price) !~ '^[0-9]+(\.[0-9]+)?$' THEN format(
                'Invalid price in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.freight_value IS NULL OR TRIM(s.freight_value) !~ '^[0-9]+(\.[0-9]+)?$' THEN format(
                'Invalid freight_value in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.seller_zip IS NULL OR s.seller_zip !~ '^[0-9]+$' THEN format(
                'Invalid seller_zip in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.seller_city IS NULL THEN format(
                'NULL seller_city in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            WHEN s.seller_state IS NULL THEN format(
                'NULL seller_state in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
            ELSE format(
                'Unknown validation error in table staging_user_order_items, item_id %s',
                COALESCE(s.item_id::text, 'NULL')
            )
        END AS rejected_reason
    FROM scoped_items s
    LEFT JOIN valid_items v
        ON s.request_id = v.request_id
       AND s.order_id = v.order_id
       AND (CASE WHEN s.item_id ~ '^[0-9]+$' THEN s.item_id::INTEGER ELSE NULL END) = v.item_id
    WHERE v.request_id IS NULL
),
inserted_items AS (
    INSERT INTO final_user_order_items (
        request_id,
        order_id,
        item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value,
        product_category_name,
        seller_zip,
        seller_city,
        seller_state,
        ingested_at
    )
    SELECT
        request_id,
        order_id,
        item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value,
        product_category_name,
        seller_zip,
        seller_city,
        seller_state,
        ingested_at
    FROM valid_items
    ON CONFLICT (request_id, item_id) DO UPDATE SET
        order_id = EXCLUDED.order_id,
        product_id = EXCLUDED.product_id,
        seller_id = EXCLUDED.seller_id,
        shipping_limit_date = EXCLUDED.shipping_limit_date,
        price = EXCLUDED.price,
        freight_value = EXCLUDED.freight_value,
        product_category_name = EXCLUDED.product_category_name,
        seller_zip = EXCLUDED.seller_zip,
        seller_city = EXCLUDED.seller_city,
        seller_state = EXCLUDED.seller_state,
        ingested_at = EXCLUDED.ingested_at
    RETURNING request_id, item_id
)
INSERT INTO rejected_user_order_items (
    request_id, order_id, item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value, product_category_name,
    seller_zip, seller_city, seller_state,
    rejected_reason
)
SELECT
    request_id, order_id, item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value, product_category_name,
    seller_zip, seller_city, seller_state,
    rejected_reason
FROM invalid_items;

-- ----------------------------------------------------------------
-- Ongoing seller history prep (for downstream feature engineering)
-- ----------------------------------------------------------------
WITH current_request_seller_orders AS (
    SELECT
        o.request_id,
        o.order_id,
        i.seller_id,
        o.purchase_date AS cutoff_date,
        SUM(i.price)::NUMERIC(12,2) AS order_seller_price,
        SUM(i.freight_value)::NUMERIC(12,2) AS order_seller_freight,
        COUNT(*)::INTEGER AS num_order_items
    FROM final_user_orders AS o
    INNER JOIN final_user_order_items AS i
        ON o.request_id = i.request_id
       AND o.order_id = i.order_id
    WHERE o.request_id = :request_id
    GROUP BY o.request_id, o.order_id, i.seller_id, o.purchase_date
)
INSERT INTO seller_order_history_base (
    source_type,
    request_id,
    order_id,
    seller_id,
    cutoff_date,
    order_seller_price,
    order_seller_freight,
    num_order_items
)
SELECT
    'online'::TEXT AS source_type,
    request_id,
    order_id,
    seller_id,
    cutoff_date,
    order_seller_price,
    order_seller_freight,
    num_order_items
FROM current_request_seller_orders
ON CONFLICT (order_id, seller_id) DO UPDATE SET
    request_id = EXCLUDED.request_id,
    cutoff_date = EXCLUDED.cutoff_date,
    order_seller_price = EXCLUDED.order_seller_price,
    order_seller_freight = EXCLUDED.order_seller_freight,
    num_order_items = EXCLUDED.num_order_items;


