-- ============================================================================
-- OLIST E-COMMERCE: DATA INSPECTION & PROFILING
-- ============================================================================
-- Purpose  : Comprehensive inspection of raw data quality before cleaning
-- Database : PostgreSQL (adapt EXTRACT / PERCENTILE_CONT for SQLite/MySQL)
-- Dataset  : Brazilian E-Commerce (Olist), Sept 2016 – Oct 2018
-- Author   : [Your Name]
-- ============================================================================


-- ============================================================================
-- SECTION 1: TABLE STRUCTURE & ROW COUNTS
-- ============================================================================

-- 1.1 Row counts for every table in the dataset
-- Expected: orders ≈ 99K, items ≈ 113K, customers ≈ 99K, payments ≈ 104K,
--           reviews ≈ 99K, products ≈ 33K, sellers ≈ 3K
SELECT 'orders'                AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL SELECT 'order_items',               COUNT(*)              FROM order_items
UNION ALL SELECT 'customers',                 COUNT(*)              FROM customers
UNION ALL SELECT 'payments',                  COUNT(*)              FROM payments
UNION ALL SELECT 'reviews',                   COUNT(*)              FROM reviews
UNION ALL SELECT 'products',                  COUNT(*)              FROM products
UNION ALL SELECT 'sellers',                   COUNT(*)              FROM sellers
UNION ALL SELECT 'category_translation',      COUNT(*)              FROM category_translation
UNION ALL SELECT 'geolocation',               COUNT(*)              FROM geolocation
ORDER BY row_count DESC;


-- ============================================================================
-- SECTION 2: PRIMARY KEY & DUPLICATE CHECKS
-- ============================================================================

-- 2.1 Validate uniqueness of primary keys across all dimension tables
SELECT 'orders'   AS tbl, COUNT(order_id)   AS total, COUNT(DISTINCT order_id)   AS uniq, COUNT(order_id)   - COUNT(DISTINCT order_id)   AS dups FROM orders
UNION ALL
SELECT 'products',        COUNT(product_id),          COUNT(DISTINCT product_id),          COUNT(product_id) - COUNT(DISTINCT product_id) FROM products
UNION ALL
SELECT 'sellers',         COUNT(seller_id),           COUNT(DISTINCT seller_id),           COUNT(seller_id)  - COUNT(DISTINCT seller_id)  FROM sellers
UNION ALL
SELECT 'customers',       COUNT(customer_id),         COUNT(DISTINCT customer_id),         COUNT(customer_id)- COUNT(DISTINCT customer_id)FROM customers;
-- RESULT: All PKs are unique ✓

-- 2.2 Reviews: known duplicate issue
-- review_id is NOT a reliable PK — 814 duplicates exist
SELECT
    COUNT(*)                                    AS total_rows,
    COUNT(DISTINCT review_id)                   AS unique_review_ids,
    COUNT(DISTINCT order_id)                    AS unique_order_ids,
    COUNT(*) - COUNT(DISTINCT review_id)        AS dup_review_ids,
    COUNT(*) - COUNT(DISTINCT order_id)         AS orders_with_multi_reviews
FROM reviews;

-- 2.3 Inspect a sample of orders with multiple reviews
-- Question: Do multi-review orders have conflicting scores?
SELECT
    order_id,
    COUNT(*)                AS review_count,
    MIN(review_score)       AS min_score,
    MAX(review_score)       AS max_score,
    MAX(review_score) - MIN(review_score) AS score_spread
FROM reviews
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY score_spread DESC
LIMIT 10;

-- 2.4 Customers: customer_id vs customer_unique_id
-- customer_id is per-order, customer_unique_id is the real person
SELECT
    COUNT(DISTINCT customer_id)        AS customer_ids,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    ROUND(COUNT(DISTINCT customer_id)::numeric
        / COUNT(DISTINCT customer_unique_id), 2) AS orders_per_customer
FROM customers;
-- INSIGHT: Tells us the repeat purchase rate


-- ============================================================================
-- SECTION 3: NULL VALUE ANALYSIS
-- ============================================================================

-- 3.1 Orders table: comprehensive null audit
SELECT
    COUNT(*)                                                                    AS total,
    SUM(CASE WHEN order_id                      IS NULL THEN 1 ELSE 0 END)     AS null_order_id,
    SUM(CASE WHEN customer_id                   IS NULL THEN 1 ELSE 0 END)     AS null_customer_id,
    SUM(CASE WHEN order_status                  IS NULL THEN 1 ELSE 0 END)     AS null_status,
    SUM(CASE WHEN order_purchase_timestamp      IS NULL THEN 1 ELSE 0 END)     AS null_purchase_ts,
    SUM(CASE WHEN order_approved_at             IS NULL THEN 1 ELSE 0 END)     AS null_approved,
    SUM(CASE WHEN order_delivered_carrier_date  IS NULL THEN 1 ELSE 0 END)     AS null_carrier,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END)     AS null_delivered,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END)     AS null_estimated
FROM orders;

-- 3.2 Cross-tab: null delivery dates by order status
-- Expectation: Nulls should correlate with non-delivered statuses
SELECT
    order_status,
    COUNT(*)                                                                       AS orders,
    SUM(CASE WHEN order_approved_at             IS NULL THEN 1 ELSE 0 END)         AS null_approved,
    SUM(CASE WHEN order_delivered_carrier_date  IS NULL THEN 1 ELSE 0 END)         AS null_shipped,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END)         AS null_delivered,
    ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END)
        / COUNT(*), 1)                                                             AS pct_null_delivered
FROM orders
GROUP BY order_status
ORDER BY orders DESC;
-- ANOMALY: 8 orders with status='delivered' but NULL delivery date

-- 3.3 Inspect the 8 anomalous delivered orders
SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;
-- DECISION: Exclude these 8 from delivery time analysis

-- 3.4 Products: null pattern analysis
-- Are nulls random or systematic?
SELECT
    COUNT(*)                                                                AS total,
    SUM(CASE WHEN product_category_name       IS NULL THEN 1 ELSE 0 END)   AS null_category,
    SUM(CASE WHEN product_name_lenght         IS NULL THEN 1 ELSE 0 END)   AS null_name_len,
    SUM(CASE WHEN product_description_lenght  IS NULL THEN 1 ELSE 0 END)   AS null_desc_len,
    SUM(CASE WHEN product_photos_qty          IS NULL THEN 1 ELSE 0 END)   AS null_photos,
    SUM(CASE WHEN product_weight_g            IS NULL THEN 1 ELSE 0 END)   AS null_weight,
    SUM(CASE WHEN product_length_cm           IS NULL THEN 1 ELSE 0 END)   AS null_length
FROM products;
-- FINDING: 610 products missing category AND all metadata simultaneously
--          2 additional products missing only physical dimensions
--          Pattern suggests 610 incomplete product registrations

-- 3.5 Reviews: comment availability
SELECT
    COUNT(*)                                                                   AS total,
    SUM(CASE WHEN review_comment_title   IS NOT NULL THEN 1 ELSE 0 END)       AS has_title,
    SUM(CASE WHEN review_comment_message IS NOT NULL THEN 1 ELSE 0 END)       AS has_message,
    ROUND(100.0 * SUM(CASE WHEN review_comment_message IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_comment
FROM reviews;
-- FINDING: ~41% of reviews include text comments — useful for future NLP analysis

-- 3.6 Do low-score reviews have more comments? (data quality insight)
SELECT
    review_score,
    COUNT(*)                                                                   AS total,
    SUM(CASE WHEN review_comment_message IS NOT NULL THEN 1 ELSE 0 END)       AS has_comment,
    ROUND(100.0 * SUM(CASE WHEN review_comment_message IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_commented
FROM reviews
GROUP BY review_score
ORDER BY review_score;
-- INSIGHT: Dissatisfied customers are more likely to leave written feedback


-- ============================================================================
-- SECTION 4: REFERENTIAL INTEGRITY
-- ============================================================================

-- 4.1 Orphan checks across all foreign key relationships
SELECT 'orders→items: orders with no items'   AS check_desc,
       COUNT(*) AS affected_rows
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL

UNION ALL
SELECT 'items→orders: items with no order',
       COUNT(*)
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL
SELECT 'items→products: items with no product',
       COUNT(*)
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL
SELECT 'items→sellers: items with no seller',
       COUNT(*)
FROM order_items oi
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL
SELECT 'orders→customers: orders with no customer',
       COUNT(*)
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'orders→reviews: orders with no review',
       COUNT(*)
FROM orders o
LEFT JOIN reviews r ON o.order_id = r.order_id
WHERE r.order_id IS NULL

UNION ALL
SELECT 'orders→payments: orders with no payment',
       COUNT(*)
FROM orders o
LEFT JOIN payments p ON o.order_id = p.order_id
WHERE p.order_id IS NULL;

-- 4.2 What are the 775 orders with no items?
-- Check if they share a common status
SELECT
    order_status,
    COUNT(*) AS count
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY order_status
ORDER BY count DESC;
-- DECISION: Exclude from revenue/product analysis (INNER JOIN handles this)


-- ============================================================================
-- SECTION 5: CATEGORY TRANSLATION COVERAGE
-- ============================================================================

-- 5.1 Categories in products but missing from translation table
SELECT DISTINCT
    p.product_category_name     AS missing_category,
    COUNT(*) OVER (PARTITION BY p.product_category_name) AS product_count
FROM products p
LEFT JOIN category_translation ct ON p.product_category_name = ct.product_category_name
WHERE ct.product_category_name IS NULL
  AND p.product_category_name IS NOT NULL
ORDER BY product_count DESC;
-- FOUND: 'pc_gamer' (10 products) and
--        'portateis_cozinha_e_preparadores_de_alimentos' (3 products)

-- 5.2 Verify total category count
SELECT
    COUNT(DISTINCT p.product_category_name) AS categories_in_products,
    COUNT(DISTINCT ct.product_category_name) AS categories_in_translation,
    COUNT(DISTINCT p.product_category_name) - COUNT(DISTINCT ct.product_category_name) AS gap
FROM products p
FULL OUTER JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name;


-- ============================================================================
-- SECTION 6: DATE RANGE & TEMPORAL DISTRIBUTION
-- ============================================================================

-- 6.1 Overall date range
SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order,
    MAX(order_purchase_timestamp)::date - MIN(order_purchase_timestamp)::date AS span_days
FROM orders;

-- 6.2 Monthly order volume — identify sparse boundary months
SELECT
    DATE_TRUNC('month', order_purchase_timestamp::timestamp) AS month,
    COUNT(*) AS orders,
    ROUND(SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END)::numeric
        / COUNT(*) * 100, 1) AS cancel_rate_pct
FROM orders
GROUP BY 1
ORDER BY 1;
-- SPARSE MONTHS: Sep 2016 (4), Nov 2016 (0), Dec 2016 (1),
--                Sep 2018 (16), Oct 2018 (4)
-- DECISION: Restrict analysis to Jan 2017 – Aug 2018 (20 complete months)

-- 6.3 Hourly order distribution (understand customer behavior)
SELECT
    EXTRACT(HOUR FROM order_purchase_timestamp::timestamp) AS hour_of_day,
    COUNT(*) AS orders
FROM orders
GROUP BY 1
ORDER BY 1;
-- INSIGHT: Identifies peak shopping hours for marketing targeting


-- ============================================================================
-- SECTION 7: VALUE DISTRIBUTIONS & OUTLIER DETECTION
-- ============================================================================

-- 7.1 Price distribution with percentiles
SELECT
    COUNT(*)                                                        AS items,
    MIN(price)                                                      AS min_price,
    PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY price)             AS p10,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price)             AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY price)             AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY price)             AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY price)             AS p90,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY price)             AS p99,
    MAX(price)                                                      AS max_price,
    ROUND(AVG(price)::numeric, 2)                                   AS mean_price,
    ROUND(STDDEV(price)::numeric, 2)                                AS std_price
FROM order_items;

-- 7.2 Freight value distribution
SELECT
    MIN(freight_value)                                              AS min_freight,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY freight_value)     AS median_freight,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY freight_value)     AS p90_freight,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY freight_value)     AS p99_freight,
    MAX(freight_value)                                              AS max_freight,
    ROUND(AVG(freight_value)::numeric, 2)                           AS mean_freight,
    SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END)             AS zero_freight_items
FROM order_items;

-- 7.3 Items per order distribution
SELECT
    items_per_order,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct
FROM (
    SELECT order_id, COUNT(*) AS items_per_order
    FROM order_items
    GROUP BY order_id
) sub
GROUP BY items_per_order
ORDER BY items_per_order;

-- 7.4 Payment anomalies
SELECT
    payment_type,
    COUNT(*) AS count,
    SUM(CASE WHEN payment_value = 0     THEN 1 ELSE 0 END) AS zero_value,
    SUM(CASE WHEN payment_installments = 0 THEN 1 ELSE 0 END) AS zero_installments,
    MIN(payment_value) AS min_val,
    MAX(payment_value) AS max_val,
    ROUND(AVG(payment_value)::numeric, 2) AS avg_val
FROM payments
GROUP BY payment_type
ORDER BY count DESC;

-- 7.5 Review score distribution with percentages
SELECT
    review_score,
    COUNT(*)                                            AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1)  AS pct,
    SUM(COUNT(*)) OVER (ORDER BY review_score)          AS cumulative
FROM reviews
GROUP BY review_score
ORDER BY review_score;

-- 7.6 Order status distribution
SELECT
    order_status,
    COUNT(*)                                            AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1)  AS pct
FROM orders
GROUP BY order_status
ORDER BY count DESC;


-- ============================================================================
-- SECTION 8: GEOGRAPHIC DISTRIBUTION
-- ============================================================================

-- 8.1 Customer concentration by state
SELECT
    customer_state,
    COUNT(*)                                            AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1)  AS pct
FROM customers
GROUP BY customer_state
ORDER BY customers DESC
LIMIT 10;

-- 8.2 Seller concentration by state
SELECT
    seller_state,
    COUNT(*)                                            AS sellers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1)  AS pct
FROM sellers
GROUP BY seller_state
ORDER BY sellers DESC
LIMIT 10;
-- INSIGHT: Compare seller vs customer distribution — are sellers co-located
--          with demand, or is there a geographic mismatch driving long deliveries?

-- 8.3 Geolocation data quality
SELECT
    COUNT(*) AS total_points,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS unique_zips,
    ROUND(COUNT(*)::numeric / COUNT(DISTINCT geolocation_zip_code_prefix), 1) AS avg_points_per_zip
FROM geolocation;


-- ============================================================================
-- INSPECTION SUMMARY
-- ============================================================================
/*
 FINDING                           | RECORDS   | SEVERITY | ACTION
 ----------------------------------|-----------|----------|---------------------------------------
 Duplicate review_ids              | 814       | Medium   | Dedup: keep most recent per order
 Orders with multiple reviews      | 547       | Medium   | Resolved by dedup above
 NULL product categories           | 610       | Low      | Label as 'unknown'
 Missing category translations     | 2         | Low      | Manually add English names
 Delivered orders with NULL date   | 8         | Low      | Exclude from delivery calculations
 Orders with no line items         | 775       | Medium   | Exclude via INNER JOIN
 Sparse boundary months            | ~25       | High     | Restrict to Jan 2017 – Aug 2018
 Zero-value payments               | 9         | Low      | Flag as anomaly
 'not_defined' payment type        | 3         | Low      | Flag as anomaly
 Missing product dimensions        | 2         | Low      | Exclude from weight analysis only
 Geolocation multi-point per zip   | ~1M       | Medium   | Aggregate to avg lat/lng per prefix
 Portuguese category names         | 73        | High     | Join translation table
 Column name typos in source       | 2 cols    | Low      | Rename in clean table
*/
