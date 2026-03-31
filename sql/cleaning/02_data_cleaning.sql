-- ============================================================================
-- OLIST E-COMMERCE: DATA CLEANING & PREPARATION
-- ============================================================================
-- Purpose  : Clean raw tables and build an analytical base for exploration
-- Database : PostgreSQL (adapt for SQLite/MySQL as needed)
-- Depends  : Raw tables loaded from CSV files
-- Output   : Cleaned tables + master analytical view + order-level summary
-- Author   : [Your Name]
-- ============================================================================


-- ============================================================================
-- STEP 1: FIX CATEGORY TRANSLATION TABLE
-- ============================================================================
-- Two product categories are missing from the translation table.
-- We add them before any joins occur.

INSERT INTO category_translation (product_category_name, product_category_name_english)
VALUES
    ('pc_gamer', 'pc_gaming'),
    ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_processors')
ON CONFLICT (product_category_name) DO NOTHING;

-- Verify: should now cover all 73 categories + 'unknown' handled later
SELECT COUNT(*) AS translation_count FROM category_translation;


-- ============================================================================
-- STEP 2: CLEAN REVIEWS — DEDUPLICATE
-- ============================================================================
-- Problem:  814 duplicate review_ids; 547 orders have 2+ reviews.
-- Strategy: Keep the MOST RECENT review per order (by review_answer_timestamp).
--           If timestamps tie, keep the higher review score.
-- Rationale: The most recent review best reflects the customer's final sentiment.

DROP TABLE IF EXISTS reviews_clean;

CREATE TABLE reviews_clean AS
SELECT DISTINCT ON (order_id)
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date::timestamp AS review_creation_date,
    review_answer_timestamp::timestamp AS review_answer_timestamp,
    -- Derived: did the customer leave a written comment?
    CASE WHEN review_comment_message IS NOT NULL THEN TRUE ELSE FALSE END AS has_comment
FROM reviews
ORDER BY order_id,
         review_answer_timestamp DESC,
         review_score DESC;

-- Verify: exactly 1 review per order
SELECT
    COUNT(*) AS total_reviews,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS should_be_zero
FROM reviews_clean;


-- ============================================================================
-- STEP 3: CLEAN PRODUCTS — HANDLE NULLS + JOIN TRANSLATION
-- ============================================================================
-- Problem:  610 products have NULL category + all metadata NULL simultaneously.
--           2 additional products have NULL dimensions only.
-- Strategy: Replace NULL category with 'unknown', join English translations,
--           rename typo columns (lenght → length).

DROP TABLE IF EXISTS products_clean;

CREATE TABLE products_clean AS
SELECT
    p.product_id,
    COALESCE(p.product_category_name, 'unknown')          AS product_category_name,
    COALESCE(ct.product_category_name_english, 'unknown') AS product_category_english,
    p.product_name_lenght                                  AS product_name_length,
    p.product_description_lenght                           AS product_description_length,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    -- Derived: product volume in cm³ for freight analysis
    CASE
        WHEN p.product_length_cm IS NOT NULL
         AND p.product_height_cm IS NOT NULL
         AND p.product_width_cm  IS NOT NULL
        THEN p.product_length_cm * p.product_height_cm * p.product_width_cm
    END AS product_volume_cm3,
    -- Derived: product size tier
    CASE
        WHEN p.product_weight_g IS NULL THEN 'unknown'
        WHEN p.product_weight_g <= 500  THEN 'small'
        WHEN p.product_weight_g <= 2000 THEN 'medium'
        WHEN p.product_weight_g <= 10000 THEN 'large'
        ELSE 'extra_large'
    END AS product_size_tier
FROM products p
LEFT JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name;

-- Verify translation coverage
SELECT
    product_category_english,
    COUNT(*) AS products
FROM products_clean
WHERE product_category_english = 'unknown'
GROUP BY 1;


-- ============================================================================
-- STEP 4: CLEAN ORDERS — CAST DATES + CREATE DERIVED COLUMNS
-- ============================================================================
-- Creates all time-based metrics needed for every downstream analysis.

DROP TABLE IF EXISTS orders_clean;

CREATE TABLE orders_clean AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,

    -- Cast all date columns to proper timestamps
    o.order_purchase_timestamp::timestamp          AS order_purchase_timestamp,
    o.order_approved_at::timestamp                 AS order_approved_at,
    o.order_delivered_carrier_date::timestamp      AS order_delivered_carrier_date,
    o.order_delivered_customer_date::timestamp     AS order_delivered_customer_date,
    o.order_estimated_delivery_date::timestamp     AS order_estimated_delivery_date,

    -- Derived: calendar dimensions for grouping
    DATE_TRUNC('month', o.order_purchase_timestamp::timestamp)   AS order_month,
    DATE_TRUNC('week', o.order_purchase_timestamp::timestamp)    AS order_week,
    EXTRACT(YEAR FROM o.order_purchase_timestamp::timestamp)     AS order_year,
    EXTRACT(QUARTER FROM o.order_purchase_timestamp::timestamp)  AS order_quarter,
    EXTRACT(MONTH FROM o.order_purchase_timestamp::timestamp)    AS order_month_num,
    EXTRACT(DOW FROM o.order_purchase_timestamp::timestamp)      AS order_day_of_week,
    EXTRACT(HOUR FROM o.order_purchase_timestamp::timestamp)     AS order_hour,

    -- Derived: delivery time metrics (only for delivered orders with valid dates)
    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
                o.order_delivered_customer_date::timestamp
                - o.order_purchase_timestamp::timestamp
             )) / 86400.0, 1)
    END AS delivery_days,

    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
                o.order_delivered_customer_date::timestamp
                - o.order_estimated_delivery_date::timestamp
             )) / 86400.0, 1)
    END AS delay_days,

    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
         AND o.order_delivered_customer_date::timestamp > o.order_estimated_delivery_date::timestamp
        THEN TRUE
        ELSE FALSE
    END AS is_late,

    -- Derived: seller handling time (purchase → carrier)
    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
                o.order_delivered_carrier_date::timestamp
                - o.order_purchase_timestamp::timestamp
             )) / 86400.0, 1)
    END AS handling_days,

    -- Derived: carrier transit time (carrier → customer)
    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
         AND o.order_delivered_customer_date IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
                o.order_delivered_customer_date::timestamp
                - o.order_delivered_carrier_date::timestamp
             )) / 86400.0, 1)
    END AS transit_days,

    -- Derived: approval speed (purchase → approval)
    CASE
        WHEN o.order_approved_at IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
                o.order_approved_at::timestamp
                - o.order_purchase_timestamp::timestamp
             )) / 3600.0, 1)
    END AS approval_hours,

    -- Derived: delivery buffer (how much earlier than estimate)
    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
                o.order_estimated_delivery_date::timestamp
                - o.order_purchase_timestamp::timestamp
             )) / 86400.0, 1)
    END AS estimated_delivery_days

FROM orders o;

-- Verify derived columns with a quick summary
SELECT
    COUNT(*) AS total_orders,
    SUM(CASE WHEN delivery_days IS NOT NULL THEN 1 ELSE 0 END) AS has_delivery_time,
    ROUND(AVG(delivery_days)::numeric, 1)    AS avg_delivery_days,
    ROUND(AVG(handling_days)::numeric, 1)    AS avg_handling_days,
    ROUND(AVG(transit_days)::numeric, 1)     AS avg_transit_days,
    ROUND(AVG(delay_days)::numeric, 1)       AS avg_delay_days,
    SUM(CASE WHEN is_late THEN 1 ELSE 0 END) AS late_count,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN delivery_days IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS late_pct
FROM orders_clean;


-- ============================================================================
-- STEP 5: CLEAN PAYMENTS — FLAG ANOMALIES + AGGREGATE
-- ============================================================================
-- Preserves all rows but flags the 12 anomalous records.

DROP TABLE IF EXISTS payments_clean;

CREATE TABLE payments_clean AS
SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value,
    CASE
        WHEN payment_value = 0            THEN TRUE
        WHEN payment_type = 'not_defined' THEN TRUE
        ELSE FALSE
    END AS is_anomaly
FROM payments;

-- Pre-aggregate payment info to order level for easy joining
DROP TABLE IF EXISTS payments_order_agg;

CREATE TABLE payments_order_agg AS
SELECT
    order_id,
    COUNT(*) AS payment_count,
    (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS primary_payment_type,
    MAX(payment_installments)       AS max_installments,
    ROUND(SUM(payment_value)::numeric, 2) AS total_payment_value,
    -- Count distinct payment methods used
    COUNT(DISTINCT payment_type)     AS payment_methods_used,
    -- Flag multi-method orders
    CASE WHEN COUNT(DISTINCT payment_type) > 1 THEN TRUE ELSE FALSE END AS is_multi_payment
FROM payments_clean
WHERE is_anomaly = FALSE
GROUP BY order_id;


-- ============================================================================
-- STEP 6: CLEAN GEOLOCATION — AGGREGATE TO ZIP PREFIX LEVEL
-- ============================================================================
-- Raw data has multiple lat/lng points per zip — average them down.

DROP TABLE IF EXISTS geolocation_clean;

CREATE TABLE geolocation_clean AS
SELECT
    geolocation_zip_code_prefix,
    ROUND(AVG(geolocation_lat)::numeric, 6)              AS avg_lat,
    ROUND(AVG(geolocation_lng)::numeric, 6)              AS avg_lng,
    MODE() WITHIN GROUP (ORDER BY geolocation_city)       AS city,
    MODE() WITHIN GROUP (ORDER BY geolocation_state)      AS state,
    COUNT(*) AS point_count
FROM geolocation
GROUP BY geolocation_zip_code_prefix;


-- ============================================================================
-- STEP 7: CREATE MASTER ANALYTICAL VIEW (Item Level)
-- ============================================================================
-- Denormalized view joining all cleaned tables for ad-hoc querying.
-- Filtered to the 20 complete months: Jan 2017 – Aug 2018.

DROP VIEW IF EXISTS vw_orders_analysis;

CREATE VIEW vw_orders_analysis AS
SELECT
    -- Order
    oc.order_id,
    oc.order_status,
    oc.order_purchase_timestamp,
    oc.order_month,
    oc.order_week,
    oc.order_year,
    oc.order_quarter,
    oc.order_month_num,
    oc.order_day_of_week,
    oc.order_hour,

    -- Delivery
    oc.delivery_days,
    oc.delay_days,
    oc.is_late,
    oc.handling_days,
    oc.transit_days,
    oc.approval_hours,
    oc.estimated_delivery_days,

    -- Customer
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    c.customer_zip_code_prefix,

    -- Items
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value AS total_item_value,

    -- Product
    pc.product_category_name,
    pc.product_category_english,
    pc.product_weight_g,
    pc.product_volume_cm3,
    pc.product_size_tier,

    -- Seller
    s.seller_city,
    s.seller_state,
    s.seller_zip_code_prefix,

    -- Review
    rc.review_score,
    rc.has_comment,
    rc.review_comment_message,

    -- Payment (order-level)
    pa.primary_payment_type,
    pa.max_installments,
    pa.total_payment_value,
    pa.is_multi_payment

FROM orders_clean oc
INNER JOIN order_items oi          ON oc.order_id    = oi.order_id
INNER JOIN customers c             ON oc.customer_id = c.customer_id
LEFT  JOIN products_clean pc       ON oi.product_id  = pc.product_id
LEFT  JOIN sellers s               ON oi.seller_id   = s.seller_id
LEFT  JOIN reviews_clean rc        ON oc.order_id    = rc.order_id
LEFT  JOIN payments_order_agg pa   ON oc.order_id    = pa.order_id
WHERE oc.order_purchase_timestamp >= '2017-01-01'
  AND oc.order_purchase_timestamp <  '2018-09-01';


-- ============================================================================
-- STEP 8: CREATE ORDER-LEVEL SUMMARY TABLE
-- ============================================================================
-- Aggregates items to one row per order — the primary table for KPIs & dashboards.

DROP TABLE IF EXISTS orders_summary;

CREATE TABLE orders_summary AS
SELECT
    oc.order_id,
    oc.order_status,
    oc.order_purchase_timestamp,
    oc.order_month,
    oc.order_week,
    oc.order_year,
    oc.order_quarter,
    oc.order_month_num,
    oc.order_day_of_week,
    oc.order_hour,
    oc.delivery_days,
    oc.handling_days,
    oc.transit_days,
    oc.delay_days,
    oc.is_late,
    oc.estimated_delivery_days,

    -- Customer
    c.customer_unique_id,
    c.customer_state,
    c.customer_city,

    -- Aggregated financials
    COUNT(oi.order_item_id)                             AS item_count,
    COUNT(DISTINCT oi.product_id)                       AS unique_products,
    COUNT(DISTINCT oi.seller_id)                        AS unique_sellers,
    ROUND(SUM(oi.price)::numeric, 2)                    AS order_revenue,
    ROUND(SUM(oi.freight_value)::numeric, 2)            AS order_freight,
    ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) AS order_total,
    ROUND((SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) * 100)::numeric, 1) AS freight_pct,

    -- Payment
    pa.primary_payment_type,
    pa.max_installments,
    pa.total_payment_value,
    pa.is_multi_payment,

    -- Review
    rc.review_score,
    rc.has_comment

FROM orders_clean oc
INNER JOIN order_items oi          ON oc.order_id    = oi.order_id
INNER JOIN customers c             ON oc.customer_id = c.customer_id
LEFT  JOIN reviews_clean rc        ON oc.order_id    = rc.order_id
LEFT  JOIN payments_order_agg pa   ON oc.order_id    = pa.order_id
WHERE oc.order_purchase_timestamp >= '2017-01-01'
  AND oc.order_purchase_timestamp <  '2018-09-01'
GROUP BY
    oc.order_id, oc.order_status, oc.order_purchase_timestamp,
    oc.order_month, oc.order_week, oc.order_year, oc.order_quarter,
    oc.order_month_num, oc.order_day_of_week, oc.order_hour,
    oc.delivery_days, oc.handling_days, oc.transit_days,
    oc.delay_days, oc.is_late, oc.estimated_delivery_days,
    c.customer_unique_id, c.customer_state, c.customer_city,
    pa.primary_payment_type, pa.max_installments, pa.total_payment_value, pa.is_multi_payment,
    rc.review_score, rc.has_comment;

-- Final verification
SELECT
    COUNT(*)                              AS total_orders,
    ROUND(AVG(order_revenue)::numeric, 2) AS avg_order_value,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery_days,
    ROUND(AVG(review_score)::numeric, 2)  AS avg_review_score
FROM orders_summary;


-- ============================================================================
-- CLEANING LOG
-- ============================================================================
/*
 # | Issue                          | Rows Affected | Action
---|--------------------------------|---------------|---------------------------------------------
 1 | Duplicate reviews              | 814 IDs       | Kept most recent review per order_id
 2 | Orders with multiple reviews   | 547 orders    | Resolved by dedup above
 3 | NULL product category          | 610 products  | Replaced with 'unknown'
 4 | Missing translations           | 2 categories  | Manually added English names
 5 | Delivered orders, NULL date    | 8 orders      | Excluded from delivery calculations
 6 | Orders with no items           | 775 orders    | Excluded via INNER JOIN
 7 | Sparse boundary months         | ~25 orders    | Filtered to Jan 2017 – Aug 2018
 8 | Zero-value payments            | 9 payments    | Flagged is_anomaly = TRUE
 9 | 'not_defined' payment type     | 3 payments    | Flagged is_anomaly = TRUE
10 | Missing product dimensions     | 2 products    | Left NULL; excluded from weight analysis
11 | Geolocation multi-points       | ~1M rows      | Aggregated to avg lat/lng per zip prefix
12 | Portuguese categories          | 73 categories | Joined translation table
13 | Column name typos              | 2 columns     | Renamed: lenght → length
14 | Delivery decomposition         | NEW           | Split into handling_days + transit_days
15 | Product size tier              | NEW           | Bucketed by weight for freight analysis
16 | Payment aggregation            | NEW           | Pre-aggregated to order level
*/
