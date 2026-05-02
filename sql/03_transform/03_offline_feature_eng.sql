--------------------------------------------------------------------------------------------------
-- File: sql/02_load/02_feature_engineering.sql
-- Purpose: To create features the ML model can use to train on as well as new meaningful features
---------------------------------------------------------------------------------------------------

BEGIN;
-- Freeze categorical encodings used by both offline training and online serving.
-- Keeping mappings in physical tables avoids accidental code drift from ad-hoc window encodings.
DROP TABLE IF EXISTS feature_product_category_encoding CASCADE;
CREATE TABLE feature_product_category_encoding AS
SELECT
    product_category,
    product_category_english,
    ROW_NUMBER() OVER (ORDER BY product_category) AS product_category_encoding
FROM final_product_category;

DROP TABLE IF EXISTS feature_seller_state_encoding CASCADE;
CREATE TABLE feature_seller_state_encoding AS
SELECT 
    DISTINCT seller_state,
    DENSE_RANK() OVER (ORDER BY seller_state) AS state_encoding
FROM final_sellers;

DROP TABLE IF EXISTS feature_payment_type_encoding CASCADE;
CREATE TABLE feature_payment_type_encoding AS
SELECT
    DISTINCT payment_type,
    DENSE_RANK() OVER (ORDER BY payment_type) AS payment_type_encoding
FROM final_payments;

-- Persistent offline seller-history baseline.
CREATE TABLE seller_order_history_base AS
SELECT
    'offline'::TEXT AS source_type,
    NULL::VARCHAR(50) AS request_id,
    items.order_id::VARCHAR(50) AS order_id,
    items.seller_id::VARCHAR(50) AS seller_id,
    orders.purchase_date AS cutoff_date,
    SUM(items.price)::NUMERIC(12,2) AS order_seller_price,
    SUM(items.freight_value)::NUMERIC(12,2) AS order_seller_freight,
    COUNT(*)::INTEGER AS num_order_items,
    NOW() AS created_at
FROM final_item_orders AS items
INNER JOIN final_orders AS orders ON items.order_id = orders.order_id
GROUP BY items.order_id, items.seller_id, orders.purchase_date;

ALTER TABLE seller_order_history_base
    ADD CONSTRAINT seller_order_history_base_pk PRIMARY KEY (order_id, seller_id);

DROP TABLE IF EXISTS customer_first_purchase_features CASCADE;
CREATE TABLE customer_first_purchase_features AS 
    -- Add payments for a single order up so each row represents a single order
    WITH aggregated_payments AS MATERIALIZED (
        SELECT DISTINCT ON (order_id)
            intermediate_payments.order_id,
            intermediate_payments.payment_type,
            payment_map.payment_type_encoding AS most_freq_payment_type_encoded,
            intermediate_payments.payment_type_count,
            SUM(intermediate_payments.installments_per_sequence) OVER (PARTITION BY intermediate_payments.order_id) AS total_installments,
            SUM(intermediate_payments.payment_value_per_sequence) OVER (PARTITION BY intermediate_payments.order_id) AS total_payment_value
        FROM (
            SELECT 
                order_id, 
                payment_type,
                COUNT(*) AS payment_type_count,
                SUM(num_installments) AS installments_per_sequence,
                SUM(payment_value) AS payment_value_per_sequence
            FROM final_payments
            GROUP BY order_id, payment_type
        ) AS intermediate_payments
        LEFT JOIN feature_payment_type_encoding AS payment_map
            ON intermediate_payments.payment_type = payment_map.payment_type
        ORDER BY intermediate_payments.order_id, intermediate_payments.payment_type_count DESC, intermediate_payments.payment_type
    ),
    -- Prediction cutoff per order (t_pred = purchase date)
    orders_with_t_pred AS MATERIALIZED (
        SELECT
            orders.order_id,
            orders.customer_id,
            orders.order_status,
            orders.purchase_date,
            orders.order_approval_date,
            orders.delivered_carrier_date,
            orders.delivered_customer_date,
            orders.estimated_delivery_date,
            orders.purchase_date AS t_pred_date
        FROM final_orders AS orders
    ),
    ----------------------------- IMPORTANT:
    ----------------------------- CURRENTLY FIGURING OUT HOW I WANT TO INCLUDE DATA RELATING TO ANSWER DATE, POST_DATE MOSTLY FIGURED OUT
    aggregated_reviews AS MATERIALIZED (
        SELECT 
            reviews.order_id,
            -- Get average review score for an order
            AVG(reviews.review_score) AS average_review_score,
            -- Binary encode if any review had a message
            MAX(CASE
                    WHEN reviews.comment_message IS NOT NULL THEN 1
                    ELSE 0 END) AS has_review_message,
            -- Proportion of reviews that had a message
            COUNT(reviews.comment_message)::FLOAT / NULLIF(COUNT(*), 0) AS has_message_proportion,
            -- Binary encode if there are multiple reviews
            CASE
                WHEN COUNT(*) > 1 THEN 1
                ELSE 0 END AS has_multiple_reviews,
            -- Number of reviews per order
            COUNT(*) AS num_reviews,
            -- Range of review dates
            MAX(reviews.post_date) - MIN(reviews.post_date) AS review_date_range,
            -- date of first review
            MIN(reviews.post_date) AS first_review_date,
            -- date of latest review
            MAX(reviews.post_date) AS latest_review_date,
            -- Binary encode if any review received an answer
            CASE
                WHEN COUNT(reviews.answer_date) FILTER (WHERE reviews.answer_date <= orders.t_pred_date) > 0 THEN 1
                ELSE 0 END AS has_review_answer,
            -- proportion of answered reviews to reviews opened for an order
            COUNT(reviews.answer_date) FILTER (WHERE reviews.answer_date <= orders.t_pred_date)::FLOAT / NULLIF(COUNT(*), 0) AS received_answer_proportion,
            -- max time taken to receive answer to a review
            MAX(CASE 
                    WHEN reviews.answer_date IS NULL OR reviews.answer_date > orders.t_pred_date THEN orders.t_pred_date - reviews.post_date
                    ELSE reviews.answer_date - reviews.post_date END) AS max_answer_time_days,
            -- min time taken to receive answer to a review
            MIN(CASE
                    WHEN reviews.answer_date IS NULL OR reviews.answer_date > orders.t_pred_date THEN orders.t_pred_date - reviews.post_date
                    ELSE reviews.answer_date - reviews.post_date END) AS min_answer_time_days
        FROM final_reviews AS reviews
        INNER JOIN orders_with_t_pred AS orders ON reviews.order_id = orders.order_id
        WHERE reviews.post_date <= orders.t_pred_date
        GROUP BY reviews.order_id, orders.t_pred_date
    ),
    distinct_seller_states AS (
        SELECT 
            order_id, 
            CASE 
                WHEN COUNT(DISTINCT sellers.seller_state) > 1 THEN 1 
                ELSE 0 END AS has_multiple_seller_states, 
            COUNT(DISTINCT sellers.seller_state) AS num_seller_states 
        FROM final_item_orders ord LEFT JOIN final_sellers sellers ON ord.seller_id = sellers.seller_id
        GROUP BY order_id
    ),
    order_item_parents_joined AS MATERIALIZED (
        SELECT 
            items.order_id, items.product_id AS items_product_id, items.seller_id AS items_seller_id, items.shipping_limit_date, items.price, items.freight_value,
            products.product_category_name,
            category.product_category, category.product_category_english, category.product_category_encoding,
            sellers.seller_id, sellers.zip_code, sellers.seller_city, sellers.seller_state, seller_state_map.state_encoding,
            MAX(items.freight_value / items.price) OVER (PARTITION BY items.order_id) AS max_freight_ratio, -- Max freight/price ratio per order
            MIN(items.freight_value / items.price) OVER (PARTITION BY items.order_id) AS min_freight_ratio, -- MIN freight/Price ratio per order
            -- distinctness of sellers from different states
            distinct_state.has_multiple_seller_states, -- Has sellers from multiple different states
            distinct_state.num_seller_states -- Number of distinct seller states per order
        FROM final_item_orders AS items
        LEFT JOIN final_products AS products 
            ON items.product_id = products.product_id
        LEFT JOIN feature_product_category_encoding AS category 
            ON products.product_category_name = category.product_category
        LEFT JOIN final_sellers AS sellers
            ON items.seller_id = sellers.seller_id 
        LEFT JOIN feature_seller_state_encoding AS seller_state_map
            ON sellers.seller_state = seller_state_map.seller_state
        LEFT JOIN distinct_seller_states AS distinct_state
            ON items.order_id = distinct_state.order_id
    ), 
    most_expensive_item_rows AS ( -- Only keeps row of most expensive item per order
        SELECT DISTINCT ON (order_id)
            order_id, items_product_id, seller_id, price, freight_value, product_category, 
            product_category_encoding, zip_code, seller_city, seller_state, state_encoding
        FROM order_item_parents_joined
        ORDER BY order_id, price DESC, freight_value DESC
    ),
    most_freq_category AS MATERIALIZED (
        SELECT 
            order_id,
            product_category,
            product_category_encoding,
            COUNT(*) AS cat_count,
            SUM(price) AS total_price, -- Total merch price per product category per order
            SUM(freight_value) AS total_freight, -- Total freight per product category per order
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
            RANK() OVER (PARTITION BY order_id ORDER BY cat_count DESC, total_price DESC, total_freight DESC) as tiebreak_rank
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
            SUM(price) + SUM(freight_value) AS total_value, -- for ranking based on sellers total order value
            -- Engineered features related to sellers 
            CASE 
                WHEN COUNT(*) > 1 THEN 1
                ELSE 0 END AS has_duplicate_sellers,

            CASE
                WHEN COUNT(seller_id) OVER (PARTITION BY order_id) > 1 THEN 1
                ELSE 0 END AS has_multiple_sellers,

            COUNT(seller_id) OVER (PARTITION BY order_id) AS num_distinct_sellers
        FROM order_item_parents_joined 
        GROUP BY order_id, seller_id, zip_code, seller_city, seller_state, state_encoding -- Assuming zip, city, and state stay consistent for each seller id
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
            RANK() OVER (PARTITION BY base.order_id ORDER BY base.total_value DESC) as tiebreak_rank
        FROM most_valuable_seller AS base
    ),
    item_orders_features AS MATERIALIZED (
        SELECT 
            agg.order_id,
            -- aggregate function values 
            agg.num_items_in_order, agg.total_freight_value, agg.total_merch_value, agg.total_order_value, agg.avg_price, agg.price_std, agg.min_price, 
            agg.price_range, agg.freight_price_ratio, agg.max_freight_ratio, agg.min_freight_ratio, agg.has_multiple_seller_states, agg.num_seller_states, 
            agg.latest_shipping_limit_date, agg.shipping_window_days,
            -- most_expensive_item_rows table columns
            exp.items_product_id, exp.price AS most_exp_price, exp.freight_value AS most_exp_freight, 
            exp.product_category AS most_exp_prod_category, exp.product_category_encoding AS most_exp_encoded_category,
            -- ranked_freq_category table columns
            freq_cat.product_category AS most_freq_category, freq_cat.product_category_encoding AS most_freq_encoded_category, 
            freq_cat.num_distinct_categories, freq_cat.most_freq_cat_concentration,
            -- ranked_val_seller table columns
            val_seller.seller_id AS val_seller_id, val_seller.zip_code AS val_seller_zip, val_seller.seller_city AS val_seller_city, 
            val_seller.seller_state AS val_seller_state, val_seller.state_encoding AS val_seller_encoded_state, val_seller.has_duplicate_sellers, 
            val_seller.has_multiple_sellers, val_seller.num_distinct_sellers
            FROM (
                SELECT
                    order_id,
                    -- aggregate functions
                    COUNT(*) AS num_items_in_order,
                    SUM(freight_value) AS total_freight_value,
                    SUM(price) AS total_merch_value,
                    SUM(freight_value) + SUM(price) AS total_order_value,
                    AVG(price) AS avg_price,
                    COALESCE(STDDEV_SAMP(price), 0) AS price_std,
                    MIN(price) AS min_price,
                    MAX(price) - MIN(price) AS price_range,
                    SUM(freight_value) / SUM(price) AS freight_price_ratio,
                    -- use MAX() to aggregate following is fine because the window function partitioned by order_id
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
            LEFT JOIN (SELECT * FROM ranked_freq_category WHERE tiebreak_rank = 1) AS freq_cat ON agg.order_id = freq_cat.order_id -- Join data of an order's most frequent product category
            LEFT JOIN (SELECT * FROM ranked_valuable_seller WHERE tiebreak_rank = 1) AS val_seller ON agg.order_id = val_seller.order_id -- Join data of an order's most valuable seller
        ),
    -- Historical data will be done after joining with final_orders
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
    ),
    orders_target_features AS MATERIALIZED ( -- creates target features for each order and imputes missing order approval dates
        SELECT
            orders.order_id,
            orders.customer_id,
            orders.order_status,
            orders.purchase_date,
            orders.t_pred_date,
            COALESCE(orders.order_approval_date, orders.purchase_date) AS order_approval_date, -- impute NULL with purchase date 
            orders.delivered_carrier_date, -- impute with shipping_limit_date if NULL after the main joins later
            orders.delivered_customer_date,
            orders.estimated_delivery_date,
            -- Create target features
            COUNT(*) OVER (PARTITION BY cust.customer_unique_id) AS total_purchases_by_customer,
            LEAD(orders.purchase_date) OVER (PARTITION BY cust.customer_unique_id ORDER BY orders.purchase_date) AS second_purchase_date,
            -- customer features
            cust.customer_unique_id, 
            cust.zip_code AS customer_zip,
            cust.city,
            cust.customer_state
        FROM orders_with_t_pred AS orders
        LEFT JOIN final_customers AS cust ON orders.customer_id = cust.customer_id
    )
    -- Make the appropriate joins of data related to the first order per customer
    SELECT DISTINCT ON (orders.customer_unique_id) -- Get only the first purchase of a customer
        -- raw and imputed column data from orders_imputed cte
        orders.order_id, orders.customer_id, orders.order_status, orders.purchase_date, orders.order_approval_date, 
        orders.t_pred_date,
        COALESCE(orders.delivered_carrier_date, items.latest_shipping_limit_date) AS delivered_carrier_date, 
        orders.delivered_customer_date, orders.estimated_delivery_date, orders.delivered_customer_date - orders.purchase_date AS total_order_duration_days,
        EXTRACT(MONTH FROM orders.purchase_date) AS purchase_month, EXTRACT(DOW FROM orders.purchase_date) AS purchase_day_of_week, 
        CASE 
            WHEN EXTRACT(DOW FROM orders.purchase_date) IN (0, 6) THEN 1
            ELSE 0 END AS purchased_on_weekend,
        -- Target features
        CASE
            WHEN orders.total_purchases_by_customer > 1 THEN 1
            ELSE 0 END AS has_second_purchase,
        orders.second_purchase_date - orders.purchase_date AS days_until_second_purchase,
        -- features created from final_orders
        CASE 
            WHEN orders.delivered_customer_date > orders.estimated_delivery_date THEN 1
            ELSE 0 END AS late_delivery,
        orders.estimated_delivery_date - orders.delivered_customer_date AS early_delivery_days,
        orders.delivered_customer_date - orders.order_approval_date AS total_delivery_days,
        orders.delivered_customer_date - COALESCE(orders.delivered_carrier_date, items.latest_shipping_limit_date) AS carrier_to_customer_delivery_days,
        orders.order_approval_date - orders.purchase_date AS order_approval_days,
        -- Check if a customer and sellers reside in same state
        CASE
            WHEN items.has_multiple_seller_states = 1 THEN 0
            WHEN orders.customer_state = items.val_seller_state THEN 1
            ELSE 0 END AS same_state_order,
        -- features created with final_orders and reviews columns
        CASE
            WHEN reviews.first_review_date < orders.delivered_customer_date AND reviews.first_review_date < orders.estimated_delivery_date THEN 1
            ELSE 0 END AS premature_review,
        CASE -- review made on a late order past its estimated date but before it was delivered 
            WHEN reviews.first_review_date < orders.delivered_customer_date AND reviews.first_review_date > orders.estimated_delivery_date THEN 1
            ELSE 0 END AS late_delivery_review,
        COALESCE(reviews.first_review_date - orders.delivered_customer_date, -1) AS delivery_to_first_review_days,
        COALESCE(reviews.latest_review_date - orders.delivered_customer_date, -1) AS delivery_to_last_review_days,
        -- features created using shipping_limit_date from item_orders_features table
        CASE
            WHEN items.latest_shipping_limit_date < COALESCE(orders.delivered_carrier_date, items.latest_shipping_limit_date) THEN 1
            ELSE 0 END AS late_seller_dispatch,
        items.latest_shipping_limit_date - COALESCE(orders.delivered_carrier_date, items.latest_shipping_limit_date) AS seller_dispatch_before_deadline_days,
        items.latest_shipping_limit_date - orders.order_approval_date AS total_days_to_dispatch_last_item,
        -- customer features
        orders.customer_unique_id, orders.customer_zip, 
        -- features from payments
        payments.most_freq_payment_type_encoded, payments.payment_type_count, payments.total_installments, payments.total_payment_value, 
        -- features from reviews
        COALESCE(reviews.average_review_score, 0) AS average_review_score,
        COALESCE(reviews.has_review_message, 0) AS has_review_message,
        COALESCE(reviews.has_message_proportion, 0) AS has_message_proportion,
        COALESCE(reviews.has_multiple_reviews, 0) AS has_multiple_reviews,
        COALESCE(reviews.num_reviews, 0) AS num_reviews,
        CASE WHEN reviews.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_review_by_t_pred,
        reviews.review_date_range, reviews.first_review_date, reviews.latest_review_date,
        COALESCE(reviews.has_review_answer, 0) AS has_review_answer,
        COALESCE(reviews.received_answer_proportion, 0) AS received_answer_proportion,
        COALESCE(reviews.max_answer_time_days, -1) AS max_answer_time_days,
        COALESCE(reviews.min_answer_time_days, -1) AS min_answer_time_days,
        CASE WHEN COALESCE(reviews.has_review_answer, 0) = 1 THEN 1 ELSE 0 END AS has_answer_by_t_pred,
        -- features from item_orders
        items.num_items_in_order, items.total_freight_value, items.total_merch_value, items.total_order_value, items.avg_price, items.price_std, items.min_price,
        items.price_range, items.freight_price_ratio, items.max_freight_ratio, items.min_freight_ratio, items.has_multiple_seller_states, items.num_seller_states, 
        items.latest_shipping_limit_date, items.shipping_window_days, 
        -- most expensive item from order's features
        items.items_product_id AS most_exp_product_id, items.most_exp_price, items.most_exp_freight, 
        items.most_exp_prod_category, items.most_exp_encoded_category,
        -- most frequent category in order's features
        items.most_freq_category, items.most_freq_encoded_category, 
        items.num_distinct_categories, items.most_freq_cat_concentration,
        -- most valuable seller in order's features
        items.val_seller_id, items.val_seller_zip, items.val_seller_city, 
        items.val_seller_state, items.val_seller_encoded_state, items.has_duplicate_sellers, 
        items.has_multiple_sellers, items.num_distinct_sellers, 
        -- seller historical statistics 
        s_stats.avg_seller_price, s_stats.avg_seller_freight, s_stats.seller_order_volume, s_stats.seller_item_volume 
    FROM orders_target_features AS orders
    INNER JOIN aggregated_payments AS payments ON orders.order_id = payments.order_id
    LEFT JOIN aggregated_reviews AS reviews ON orders.order_id = reviews.order_id
    INNER JOIN item_orders_features AS items ON orders.order_id = items.order_id
    INNER JOIN seller_historical_data AS s_stats ON orders.order_id = s_stats.order_id AND items.val_seller_id = s_stats.seller_id
    WHERE orders.delivered_customer_date IS NOT NULL
    AND orders.order_status = 'delivered' -- Only delivered orders
    ORDER BY orders.customer_unique_id, orders.purchase_date, orders.order_id;

    -- Second SQL layer: purchase-time-safe projection for modeling
DROP VIEW IF EXISTS customer_first_purchase_features_purchase_time;
CREATE VIEW customer_first_purchase_features_purchase_time AS
SELECT
    -- core identifiers / target fields kept for downstream splitting/label building
    order_id,
    customer_id,
    order_status,
    purchase_date,
    t_pred_date,
    has_second_purchase,
    days_until_second_purchase,
    customer_unique_id,
    customer_zip,

    -- purchase-time-safe engineered features
    purchase_month,
    purchase_day_of_week,
    purchased_on_weekend,

    most_freq_payment_type_encoded,
    payment_type_count,
    total_installments,
    total_payment_value,

    num_items_in_order,
    total_freight_value,
    total_merch_value,
    total_order_value,
    avg_price,
    price_std,
    min_price,
    price_range,
    freight_price_ratio,
    max_freight_ratio,
    min_freight_ratio,
    has_multiple_seller_states,
    num_seller_states,
    latest_shipping_limit_date,
    shipping_window_days,
    most_exp_product_id,
    most_exp_price,
    most_exp_freight,
    most_exp_prod_category,
    most_exp_encoded_category,
    most_freq_category,
    most_freq_encoded_category,
    num_distinct_categories,
    most_freq_cat_concentration,
    val_seller_id,
    val_seller_zip,
    val_seller_city,
    val_seller_state,
    val_seller_encoded_state,
    has_duplicate_sellers,
    has_multiple_sellers,
    num_distinct_sellers,
    -- seller historical statistics
    avg_seller_price,
    avg_seller_freight,
    seller_order_volume,
    seller_item_volume
FROM customer_first_purchase_features;

COMMIT;

    ----- features after joining with final_orders using final_orders' columns -----
    -- did second purchase occur - target
    -- arrived after estimated delivery date: binary -
    -- time difference between estimated delivery date and actual: days -
    -- time from approved to delivered: days -
    -- time from carrier to customer: days -
    -- time for order approval: days -
    -- total_order_duration_days -
    ----- with reviews ------
    -- review made before items delivered: binary -
    -- premature review made, review made before estimated delivery time and before item delivered: binary -
    -- time between delivered and first review: days, negative means review made first -
    -- time between delivered and last review: days, negative means review made first -

    ------ with item_orders -----
    -- seller history statistics without data leakage
        -- most valuable sellers average price -
        -- most valuable sellers average freight -
        -- most valuable sellers total order count (order volume) -
        -- most valuable sellers total items sold count (item volume) -
    -- shipping_limit_date features
        -- seller dispatched late, latest_shipping_limit_date < delivered_carrier_date: binary -
        -- time between latest_shipping_limit_date and delivered_carrier_date: days, negative means seller dispatched late -
        -- time given for latest seller to dispatch item after approval, latest_shipping_limit_date - order_approval_date: days -
        -- 

    ---- aggregated values directly from order_item_parents_joined ----
            -- order_id -
            -- number of items in order -
            -- total freight value -
            -- total merchandise value -
            -- total order value -
            -- average price per item - 
            -- price standard deviation -
            -- minimum item price -
            -- price range -
            -- freight to merch ratio -
            -- max freight to merch ratio per order -
            -- min freight to merch ratio per order -
            -- has sellers from > 1 state -
            -- num seller states per order -
            -- earliest shipping limit date 
            -- shipping_window_days – max(shipping_limit_date) - min(shipping_limit_date)

            ---- most_expensive_item_rows ----
            -- most expensive product id - 
            -- most expensive item seller_id -
            -- most expensive item price -
            -- most expensive item freight value -
            -- most expensive item category -
            -- most expensive item category class encoded -
            -- most expensive item seller zip code -
            -- most expensive item seller city -
            -- most expensive item seller state -

            ---- ranked_freq_category ----
            -- most frequent category -
            -- most frequent category class encoded -
            -- number of distinct item categories -
            -- proportion of most freq category items against total items in order -

            ---- ranked_valuable_seller ----
            -- most valuable seller id -
            -- most valuable seller zip code -
            -- most valuable seller city -
            -- most valuable seller state -
            -- sellers sell multiple items, has_dupe_sellers - 
            -- number of distinct sellers -
            -- has multiple sellers -

