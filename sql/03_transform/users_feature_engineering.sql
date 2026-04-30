----------------------------------------------------------------------------------------
-- File: sql/03_transform/users_feature_engineering.sql
-- Purpose: Build one request-scoped model feature row for online inference
-- Usage: pass request_id as a SQL parameter (:request_id)
----------------------------------------------------------------------------------------
CREATE TABLE users_feature_engineering AS
WITH aggregated_payments AS MATERIALIZED (
    SELECT DISTINCT ON (payment_rollup.order_id)
        payment_rollup.order_id,
        payment_rollup.payment_type,
        payment_map.payment_type_encoding AS most_freq_payment_type_encoded,
        payment_rollup.payment_type_count,
        SUM(payment_rollup.installments_per_sequence) OVER (PARTITION BY payment_rollup.order_id) AS total_installments,
        SUM(payment_rollup.payment_value_per_sequence) OVER (PARTITION BY payment_rollup.order_id) AS total_payment_value
    FROM (
        SELECT
            p.order_id,
            p.payment_type,
            COUNT(*) AS payment_type_count,
            SUM(p.num_installments) AS installments_per_sequence,
            SUM(p.payment_value) AS payment_value_per_sequence
        FROM final_user_payments AS p
        WHERE p.request_id = :request_id
        GROUP BY p.order_id, p.payment_type
    ) AS payment_rollup
    LEFT JOIN feature_payment_type_encoding AS payment_map
        ON payment_rollup.payment_type = payment_map.payment_type
    ORDER BY payment_rollup.order_id, payment_rollup.payment_type_count DESC, payment_rollup.payment_type
),
distinct_seller_states AS (
    SELECT
        i.order_id,
        CASE WHEN COUNT(DISTINCT i.seller_state) > 1 THEN 1 ELSE 0 END AS has_multiple_seller_states,
        COUNT(DISTINCT i.seller_state) AS num_seller_states
    FROM final_user_order_items AS i
    WHERE i.request_id = :request_id
    GROUP BY i.order_id
),
order_item_parents_joined AS MATERIALIZED (
    SELECT
        i.order_id,
        i.product_id AS items_product_id,
        i.seller_id AS items_seller_id,
        i.shipping_limit_date,
        i.price,
        i.freight_value,
        i.product_category_name,
        category_map.product_category,
        category_map.product_category_english,
        category_map.product_category_encoding,
        i.seller_id AS seller_id,
        i.seller_zip AS zip_code,
        i.seller_city,
        i.seller_state,
        seller_state_map.state_encoding,
        MAX(i.freight_value / NULLIF(i.price, 0)) OVER (PARTITION BY i.order_id) AS max_freight_ratio,
        MIN(i.freight_value / NULLIF(i.price, 0)) OVER (PARTITION BY i.order_id) AS min_freight_ratio,
        distinct_state.has_multiple_seller_states,
        distinct_state.num_seller_states
    FROM final_user_order_items AS i
    LEFT JOIN feature_product_category_encoding AS category_map
        ON i.product_category_name = category_map.product_category
    LEFT JOIN feature_seller_state_encoding AS seller_state_map
        ON i.seller_state = seller_state_map.seller_state
    LEFT JOIN distinct_seller_states AS distinct_state
        ON i.order_id = distinct_state.order_id
    WHERE i.request_id = :request_id
),
most_expensive_item_rows AS (
    SELECT DISTINCT ON (order_id)
        order_id,
        items_product_id,
        seller_id,
        price,
        freight_value,
        product_category,
        product_category_encoding,
        zip_code,
        seller_city,
        seller_state,
        state_encoding
    FROM order_item_parents_joined
    ORDER BY order_id, price DESC, freight_value DESC
),
most_freq_category AS MATERIALIZED (
    SELECT
        order_id,
        product_category,
        product_category_encoding,
        COUNT(*) AS cat_count,
        SUM(price) AS total_price,
        SUM(freight_value) AS total_freight,
        COUNT(*) OVER (PARTITION BY order_id) AS num_distinct_categories
    FROM order_item_parents_joined
    GROUP BY order_id, product_category, product_category_encoding
),
ranked_freq_category AS MATERIALIZED (
    SELECT
        order_id,
        product_category,
        product_category_encoding,
        num_distinct_categories,
        cat_count::FLOAT / SUM(cat_count) OVER (PARTITION BY order_id) AS most_freq_cat_concentration,
        RANK() OVER (
            PARTITION BY order_id
            ORDER BY cat_count DESC, total_price DESC, total_freight DESC
        ) AS tiebreak_rank
    FROM most_freq_category
),
most_valuable_seller AS MATERIALIZED (
    SELECT
        order_id,
        seller_id,
        zip_code,
        seller_city,
        seller_state,
        state_encoding,
        SUM(price) + SUM(freight_value) AS total_value,
        CASE WHEN COUNT(*) > 1 THEN 1 ELSE 0 END AS has_duplicate_sellers,
        CASE WHEN COUNT(seller_id) OVER (PARTITION BY order_id) > 1 THEN 1 ELSE 0 END AS has_multiple_sellers,
        COUNT(seller_id) OVER (PARTITION BY order_id) AS num_distinct_sellers
    FROM order_item_parents_joined
    GROUP BY order_id, seller_id, zip_code, seller_city, seller_state, state_encoding
),
ranked_valuable_seller AS MATERIALIZED (
    SELECT
        base.order_id,
        base.seller_id,
        base.zip_code,
        base.seller_city,
        base.seller_state,
        base.state_encoding,
        base.has_duplicate_sellers,
        base.has_multiple_sellers,
        base.num_distinct_sellers,
        RANK() OVER (PARTITION BY base.order_id ORDER BY base.total_value DESC) AS tiebreak_rank
    FROM most_valuable_seller AS base
),
item_orders_features AS MATERIALIZED (
    SELECT
        agg.order_id,
        agg.num_items_in_order,
        agg.total_freight_value,
        agg.total_merch_value,
        agg.total_order_value,
        agg.avg_price,
        agg.price_std,
        agg.min_price,
        agg.price_range,
        agg.freight_price_ratio,
        agg.max_freight_ratio,
        agg.min_freight_ratio,
        agg.has_multiple_seller_states,
        agg.num_seller_states,
        agg.latest_shipping_limit_date,
        agg.shipping_window_days,
        exp.items_product_id,
        exp.price AS most_exp_price,
        exp.freight_value AS most_exp_freight,
        exp.product_category AS most_exp_prod_category,
        exp.product_category_encoding AS most_exp_encoded_category,
        freq_cat.product_category AS most_freq_category,
        freq_cat.product_category_encoding AS most_freq_encoded_category,
        freq_cat.num_distinct_categories,
        freq_cat.most_freq_cat_concentration,
        val_seller.seller_id AS val_seller_id,
        val_seller.zip_code AS val_seller_zip,
        val_seller.seller_city AS val_seller_city,
        val_seller.seller_state AS val_seller_state,
        val_seller.state_encoding AS val_seller_encoded_state,
        val_seller.has_duplicate_sellers,
        val_seller.has_multiple_sellers,
        val_seller.num_distinct_sellers
    FROM (
        SELECT
            order_id,
            COUNT(*) AS num_items_in_order,
            SUM(freight_value) AS total_freight_value,
            SUM(price) AS total_merch_value,
            SUM(freight_value) + SUM(price) AS total_order_value,
            AVG(price) AS avg_price,
            COALESCE(STDDEV_SAMP(price), 0) AS price_std,
            MIN(price) AS min_price,
            MAX(price) - MIN(price) AS price_range,
            SUM(freight_value) / NULLIF(SUM(price), 0) AS freight_price_ratio,
            MAX(max_freight_ratio) AS max_freight_ratio,
            MAX(min_freight_ratio) AS min_freight_ratio,
            MAX(has_multiple_seller_states) AS has_multiple_seller_states,
            MAX(num_seller_states) AS num_seller_states,
            MAX(shipping_limit_date) AS latest_shipping_limit_date,
            MAX(shipping_limit_date) - MIN(shipping_limit_date) AS shipping_window_days
        FROM order_item_parents_joined
        GROUP BY order_id
    ) AS agg
    LEFT JOIN most_expensive_item_rows AS exp ON agg.order_id = exp.order_id
    LEFT JOIN (SELECT * FROM ranked_freq_category WHERE tiebreak_rank = 1) AS freq_cat ON agg.order_id = freq_cat.order_id
    LEFT JOIN (SELECT * FROM ranked_valuable_seller WHERE tiebreak_rank = 1) AS val_seller ON agg.order_id = val_seller.order_id
),
orders_target_features AS MATERIALIZED (
    SELECT
        o.request_id,
        o.order_id,
        o.customer_id,
        o.order_status,
        o.purchase_date,
        o.customer_unique_id,
        o.customer_zip,
        o.customer_state
    FROM final_user_orders AS o
    WHERE o.request_id = :request_id
),
seller_historical_data AS MATERIALIZED (
    SELECT
        hist.order_id,
        hist.seller_id,
        COALESCE(AVG(hist.order_seller_price) OVER seller_to_date, 0) AS avg_seller_price,
        COALESCE(AVG(hist.order_seller_freight) OVER seller_to_date, 0) AS avg_seller_freight,
        COALESCE(COUNT(*) OVER seller_to_date, 0) AS seller_order_volume,
        COALESCE(SUM(hist.num_order_items) OVER seller_to_date, 0) AS seller_item_volume
    FROM seller_order_history_base AS hist
    WINDOW seller_to_date AS (
        PARTITION BY hist.seller_id
        ORDER BY hist.cutoff_date, hist.order_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    )
)
SELECT
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.purchase_date,
    orders.customer_unique_id,
    orders.customer_zip,
    EXTRACT(MONTH FROM orders.purchase_date) AS purchase_month,
    EXTRACT(DOW FROM orders.purchase_date) AS purchase_day_of_week,
    CASE WHEN EXTRACT(DOW FROM orders.purchase_date) IN (0, 6) THEN 1 ELSE 0 END AS purchased_on_weekend,
    payments.most_freq_payment_type_encoded,
    payments.payment_type_count,
    payments.total_installments,
    payments.total_payment_value,
    items.num_items_in_order,
    items.total_freight_value,
    items.total_merch_value,
    items.total_order_value,
    items.avg_price,
    items.price_std,
    items.min_price,
    items.price_range,
    items.freight_price_ratio,
    items.max_freight_ratio,
    items.min_freight_ratio,
    items.has_multiple_seller_states,
    items.num_seller_states,
    items.latest_shipping_limit_date,
    items.shipping_window_days,
    items.items_product_id AS most_exp_product_id,
    items.most_exp_price,
    items.most_exp_freight,
    items.most_exp_prod_category,
    items.most_exp_encoded_category,
    items.most_freq_category,
    items.most_freq_encoded_category,
    items.num_distinct_categories,
    items.most_freq_cat_concentration,
    items.val_seller_id,
    items.val_seller_zip,
    items.val_seller_city,
    items.val_seller_state,
    items.val_seller_encoded_state,
    items.has_duplicate_sellers,
    items.has_multiple_sellers,
    items.num_distinct_sellers,
    seller_stats.avg_seller_price,
    seller_stats.avg_seller_freight,
    seller_stats.seller_order_volume,
    seller_stats.seller_item_volume
FROM orders_target_features AS orders
INNER JOIN aggregated_payments AS payments
    ON orders.order_id = payments.order_id
INNER JOIN item_orders_features AS items
    ON orders.order_id = items.order_id
INNER JOIN seller_historical_data AS seller_stats
    ON orders.order_id = seller_stats.order_id
   AND items.val_seller_id = seller_stats.seller_id;
