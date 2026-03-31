-- ============================================================================
-- OLIST E-COMMERCE: EXPLORATORY ANALYSIS QUERIES (Phase 2)
-- ============================================================================
-- Purpose  : Targeted business questions across four analytical categories
-- Depends  : Cleaned tables from 02_data_cleaning.sql
-- Scope    : Jan 2017 – Aug 2018 (20 complete months)
-- Author   : [Your Name]
-- ============================================================================


-- ############################################################################
-- CATEGORY 1: SALES & REVENUE TRENDS
-- ############################################################################

-- 1.1 Monthly revenue, order count, and AOV time series
SELECT
    order_month,
    COUNT(DISTINCT order_id)                    AS order_count,
    ROUND(SUM(order_revenue)::numeric, 2)       AS total_revenue,
    ROUND(SUM(order_freight)::numeric, 2)       AS total_freight,
    ROUND(SUM(order_total)::numeric, 2)         AS total_gmv,
    ROUND(AVG(order_revenue)::numeric, 2)       AS avg_order_value,
    ROUND(AVG(item_count)::numeric, 1)          AS avg_items_per_order
FROM orders_summary
GROUP BY order_month
ORDER BY order_month;


-- 1.2 Year-over-year growth (Jan–Aug 2017 vs Jan–Aug 2018)
WITH yearly AS (
    SELECT
        order_year,
        COUNT(*) AS orders,
        ROUND(SUM(order_revenue)::numeric, 2) AS revenue,
        ROUND(AVG(order_revenue)::numeric, 2) AS aov,
        COUNT(DISTINCT customer_unique_id) AS unique_customers
    FROM orders_summary
    WHERE order_month_num BETWEEN 1 AND 8
    GROUP BY order_year
)
SELECT
    y18.orders AS orders_2018,
    y17.orders AS orders_2017,
    ROUND(100.0 * (y18.orders - y17.orders) / y17.orders, 1) AS order_growth_pct,
    y18.revenue AS revenue_2018,
    y17.revenue AS revenue_2017,
    ROUND(100.0 * (y18.revenue - y17.revenue) / y17.revenue, 1) AS revenue_growth_pct,
    y18.aov AS aov_2018,
    y17.aov AS aov_2017,
    y18.unique_customers AS customers_2018,
    y17.unique_customers AS customers_2017,
    ROUND(100.0 * (y18.unique_customers - y17.unique_customers)
        / y17.unique_customers, 1) AS customer_growth_pct
FROM yearly y18
JOIN yearly y17 ON y18.order_year = 2018 AND y17.order_year = 2017;


-- 1.3 Revenue by payment type
SELECT
    primary_payment_type,
    COUNT(*)                                        AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct_orders,
    ROUND(SUM(order_total)::numeric, 2)             AS total_value,
    ROUND(AVG(order_total)::numeric, 2)             AS avg_value,
    ROUND(AVG(order_revenue)::numeric, 2)           AS avg_revenue
FROM orders_summary
WHERE primary_payment_type IS NOT NULL
GROUP BY primary_payment_type
ORDER BY total_value DESC;


-- 1.4 Installment behavior: do more installments = bigger orders?
SELECT
    max_installments AS installments,
    COUNT(*)                            AS order_count,
    ROUND(AVG(order_revenue)::numeric, 2) AS avg_order_value,
    ROUND(AVG(order_total)::numeric, 2)   AS avg_total,
    ROUND(AVG(review_score)::numeric, 2)  AS avg_review_score
FROM orders_summary
WHERE primary_payment_type = 'credit_card'
  AND max_installments BETWEEN 1 AND 12
GROUP BY max_installments
ORDER BY max_installments;


-- 1.5 Revenue by day of week and hour (peak shopping windows)
SELECT
    order_day_of_week,
    CASE order_day_of_week
        WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    COUNT(*) AS order_count,
    ROUND(SUM(order_revenue)::numeric, 2) AS total_revenue,
    ROUND(AVG(order_revenue)::numeric, 2) AS avg_order_value
FROM orders_summary
GROUP BY order_day_of_week
ORDER BY order_day_of_week;


-- 1.6 Hourly order distribution
SELECT
    order_hour,
    COUNT(*) AS order_count,
    ROUND(SUM(order_revenue)::numeric, 2) AS revenue
FROM orders_summary
GROUP BY order_hour
ORDER BY order_hour;


-- 1.7 Customer geography: top 10 states by revenue
SELECT
    customer_state,
    COUNT(*) AS orders,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    ROUND(SUM(order_revenue)::numeric, 2) AS total_revenue,
    ROUND(AVG(order_revenue)::numeric, 2) AS avg_order_value,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct_orders
FROM orders_summary
GROUP BY customer_state
ORDER BY total_revenue DESC
LIMIT 10;


-- 1.8 Repeat customer analysis
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(order_revenue) AS lifetime_revenue,
        MIN(order_purchase_timestamp) AS first_order,
        MAX(order_purchase_timestamp) AS last_order
    FROM orders_summary
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN order_count = 1 THEN '1 order'
        WHEN order_count = 2 THEN '2 orders'
        WHEN order_count = 3 THEN '3 orders'
        ELSE '4+ orders'
    END AS customer_segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct_customers,
    ROUND(AVG(lifetime_revenue)::numeric, 2) AS avg_ltv,
    ROUND(SUM(lifetime_revenue)::numeric, 2) AS total_revenue,
    ROUND(100.0 * SUM(lifetime_revenue) / SUM(SUM(lifetime_revenue)) OVER(), 1) AS pct_revenue
FROM customer_orders
GROUP BY 1
ORDER BY MIN(order_count);


-- ############################################################################
-- CATEGORY 2: PRODUCT PERFORMANCE
-- ############################################################################

-- 2.1 Top 20 categories by revenue with profitability indicators
SELECT
    product_category_english,
    COUNT(DISTINCT order_id)          AS orders,
    SUM(order_item_id)                AS items_sold,
    ROUND(SUM(price)::numeric, 2)     AS total_revenue,
    ROUND(AVG(price)::numeric, 2)     AS avg_price,
    ROUND(SUM(freight_value)::numeric, 2) AS total_freight,
    ROUND(100.0 * SUM(freight_value) / NULLIF(SUM(price), 0), 1) AS freight_pct,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review
FROM vw_orders_analysis
GROUP BY product_category_english
ORDER BY total_revenue DESC
LIMIT 20;


-- 2.2 Pareto analysis: cumulative revenue concentration
WITH cat_rev AS (
    SELECT
        product_category_english,
        ROUND(SUM(price)::numeric, 2) AS revenue
    FROM vw_orders_analysis
    GROUP BY product_category_english
),
ranked AS (
    SELECT
        product_category_english,
        revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC) AS cumulative,
        SUM(revenue) OVER () AS grand_total,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rank,
        COUNT(*) OVER () AS total_categories
    FROM cat_rev
)
SELECT
    rank,
    product_category_english,
    revenue,
    ROUND(100.0 * cumulative / grand_total, 1) AS cumul_pct,
    CASE WHEN 100.0 * cumulative / grand_total <= 80 THEN 'Top 80%' ELSE 'Long Tail' END AS pareto_group
FROM ranked
ORDER BY rank;


-- 2.3 Freight-to-price ratio analysis (which categories lose margin to shipping?)
SELECT
    product_category_english,
    COUNT(*) AS items_sold,
    ROUND(AVG(price)::numeric, 2) AS avg_price,
    ROUND(AVG(freight_value)::numeric, 2) AS avg_freight,
    ROUND(100.0 * AVG(freight_value) / NULLIF(AVG(price), 0), 1) AS freight_pct,
    ROUND(AVG(product_weight_g)::numeric, 0) AS avg_weight_g,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review
FROM vw_orders_analysis
WHERE product_category_english != 'unknown'
GROUP BY product_category_english
HAVING COUNT(*) >= 100
ORDER BY freight_pct DESC
LIMIT 20;


-- 2.4 Product size tier analysis: how does weight affect freight and satisfaction?
SELECT
    pc.product_size_tier,
    COUNT(*) AS items_sold,
    ROUND(AVG(oi.price)::numeric, 2) AS avg_price,
    ROUND(AVG(oi.freight_value)::numeric, 2) AS avg_freight,
    ROUND(100.0 * AVG(oi.freight_value) / NULLIF(AVG(oi.price), 0), 1) AS freight_pct,
    ROUND(AVG(rc.review_score)::numeric, 2) AS avg_review
FROM orders_clean oc
INNER JOIN order_items oi ON oc.order_id = oi.order_id
LEFT JOIN products_clean pc ON oi.product_id = pc.product_id
LEFT JOIN reviews_clean rc ON oc.order_id = rc.order_id
WHERE oc.order_purchase_timestamp >= '2017-01-01'
  AND oc.order_purchase_timestamp < '2018-09-01'
  AND pc.product_size_tier != 'unknown'
GROUP BY pc.product_size_tier
ORDER BY AVG(oi.freight_value) DESC;


-- 2.5 Top 5 categories: monthly revenue trend
WITH top5 AS (
    SELECT product_category_english
    FROM vw_orders_analysis
    GROUP BY product_category_english
    ORDER BY SUM(price) DESC
    LIMIT 5
)
SELECT
    v.order_month,
    v.product_category_english,
    ROUND(SUM(v.price)::numeric, 2) AS monthly_revenue,
    COUNT(DISTINCT v.order_id) AS orders
FROM vw_orders_analysis v
INNER JOIN top5 t ON v.product_category_english = t.product_category_english
GROUP BY v.order_month, v.product_category_english
ORDER BY v.order_month, v.product_category_english;


-- 2.6 Product listing quality: do photos and descriptions affect reviews?
SELECT
    CASE
        WHEN pc.product_photos_qty IS NULL THEN 'unknown'
        WHEN pc.product_photos_qty = 1 THEN '1 photo'
        WHEN pc.product_photos_qty <= 3 THEN '2-3 photos'
        ELSE '4+ photos'
    END AS photo_bucket,
    COUNT(*) AS items,
    ROUND(AVG(rc.review_score)::numeric, 2) AS avg_review,
    ROUND(AVG(oi.price)::numeric, 2) AS avg_price
FROM orders_clean oc
INNER JOIN order_items oi ON oc.order_id = oi.order_id
LEFT JOIN products_clean pc ON oi.product_id = pc.product_id
LEFT JOIN reviews_clean rc ON oc.order_id = rc.order_id
WHERE oc.order_purchase_timestamp >= '2017-01-01'
  AND oc.order_purchase_timestamp < '2018-09-01'
GROUP BY 1
ORDER BY avg_review DESC;


-- ############################################################################
-- CATEGORY 3: DELIVERY & LOGISTICS
-- ############################################################################

-- 3.1 Overall delivery performance dashboard
SELECT
    COUNT(*) AS delivered_orders,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)::numeric, 1) AS median_delivery,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days)::numeric, 1) AS p90_delivery,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling_days,
    ROUND(AVG(transit_days)::numeric, 1) AS avg_transit_days,
    SUM(CASE WHEN is_late THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END) / COUNT(*), 1) AS late_pct,
    ROUND(AVG(estimated_delivery_days)::numeric, 1) AS avg_estimated_days
FROM orders_summary
WHERE delivery_days IS NOT NULL;


-- 3.2 Delivery time decomposition: handling vs transit
-- Understanding WHERE the delay happens
SELECT
    order_month,
    COUNT(*) AS orders,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling,
    ROUND(AVG(transit_days)::numeric, 1) AS avg_transit,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_total,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END) / COUNT(*), 1) AS late_pct
FROM orders_summary
WHERE delivery_days IS NOT NULL
GROUP BY order_month
ORDER BY order_month;


-- 3.3 Average delivery time by customer state
SELECT
    customer_state,
    COUNT(*) AS orders,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling,
    ROUND(AVG(transit_days)::numeric, 1) AS avg_transit,
    ROUND(AVG(delay_days)::numeric, 1)   AS avg_delay,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END) / COUNT(*), 1) AS late_pct,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review
FROM orders_summary
WHERE delivery_days IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 50
ORDER BY avg_delivery DESC;


-- 3.4 Seller state performance
SELECT
    seller_state,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling,
    ROUND(AVG(transit_days)::numeric, 1) AS avg_transit,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END)
        / COUNT(DISTINCT order_id), 1) AS late_pct
FROM vw_orders_analysis
WHERE delivery_days IS NOT NULL
GROUP BY seller_state
HAVING COUNT(DISTINCT order_id) >= 50
ORDER BY avg_delivery DESC;


-- 3.5 Same-state vs cross-state delivery comparison
SELECT
    CASE WHEN customer_state = seller_state THEN 'Same State' ELSE 'Cross State' END AS route_type,
    COUNT(*) AS items,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling,
    ROUND(AVG(transit_days)::numeric, 1) AS avg_transit,
    ROUND(AVG(freight_value)::numeric, 2) AS avg_freight,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END) / COUNT(*), 1) AS late_pct,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review
FROM vw_orders_analysis
WHERE delivery_days IS NOT NULL
GROUP BY 1;


-- 3.6 Estimated vs actual delivery: how conservative are estimates?
SELECT
    CASE
        WHEN delay_days < -10 THEN 'a. 10+ days early'
        WHEN delay_days < -5  THEN 'b. 5-10 days early'
        WHEN delay_days < 0   THEN 'c. 1-5 days early'
        WHEN delay_days <= 0  THEN 'd. On time'
        WHEN delay_days <= 5  THEN 'e. 1-5 days late'
        WHEN delay_days <= 10 THEN 'f. 5-10 days late'
        ELSE                       'g. 10+ days late'
    END AS delivery_bucket,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review
FROM orders_summary
WHERE delay_days IS NOT NULL AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- 3.7 Late delivery root cause: is it handling or transit?
SELECT
    CASE WHEN is_late THEN 'Late' ELSE 'On Time' END AS status,
    COUNT(*) AS orders,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling,
    ROUND(AVG(transit_days)::numeric, 1)  AS avg_transit,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_total,
    ROUND(AVG(estimated_delivery_days)::numeric, 1) AS avg_estimated
FROM orders_summary
WHERE delivery_days IS NOT NULL
GROUP BY 1;


-- ############################################################################
-- CATEGORY 4: CUSTOMER SATISFACTION
-- ############################################################################

-- 4.1 Review score distribution
SELECT
    review_score,
    COUNT(*)                                           AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct,
    SUM(CASE WHEN has_comment THEN 1 ELSE 0 END)      AS with_comment,
    ROUND(100.0 * SUM(CASE WHEN has_comment THEN 1 ELSE 0 END) / COUNT(*), 1) AS comment_rate
FROM orders_summary
WHERE review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;


-- 4.2 Review score by delivery outcome
SELECT
    CASE WHEN is_late THEN 'Late' ELSE 'On Time / Early' END AS delivery_status,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_score,
    ROUND(100.0 * SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_5star,
    ROUND(100.0 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_1star,
    ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_low
FROM orders_summary
WHERE review_score IS NOT NULL AND delivery_days IS NOT NULL
GROUP BY 1;


-- 4.3 Delay bands vs review score (the key causal chart)
SELECT
    CASE
        WHEN delay_days < -7  THEN 'a. 7+ days early'
        WHEN delay_days < -3  THEN 'b. 3-7 days early'
        WHEN delay_days < 0   THEN 'c. 1-3 days early'
        WHEN delay_days <= 0  THEN 'd. On time'
        WHEN delay_days <= 3  THEN 'e. 1-3 days late'
        WHEN delay_days <= 7  THEN 'f. 3-7 days late'
        ELSE                       'g. 7+ days late'
    END AS delay_bucket,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_score,
    ROUND(100.0 * SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_5star,
    ROUND(100.0 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_1star
FROM orders_summary
WHERE delay_days IS NOT NULL AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- 4.4 Lowest-rated product categories (min 50 orders)
SELECT
    product_category_english,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_score,
    ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*), 1) AS pct_low,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN delivery_days IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS late_pct,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery
FROM vw_orders_analysis
WHERE review_score IS NOT NULL
GROUP BY product_category_english
HAVING COUNT(DISTINCT order_id) >= 50
ORDER BY avg_score ASC
LIMIT 15;


-- 4.5 Average review score by customer state
SELECT
    customer_state,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_score,
    ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_low,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN delivery_days IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS late_pct
FROM orders_summary
WHERE review_score IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 50
ORDER BY avg_score ASC;


-- 4.6 Multi-factor satisfaction analysis
-- Which combination of factors produces the worst reviews?
SELECT
    CASE WHEN is_late THEN 'Late' ELSE 'On Time' END AS delivery,
    CASE WHEN freight_pct > 30 THEN 'High Freight' ELSE 'Normal Freight' END AS freight_tier,
    CASE WHEN item_count > 1 THEN 'Multi-Item' ELSE 'Single Item' END AS order_type,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_score,
    ROUND(100.0 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_1star
FROM orders_summary
WHERE review_score IS NOT NULL AND delivery_days IS NOT NULL
GROUP BY 1, 2, 3
HAVING COUNT(*) >= 30
ORDER BY avg_score ASC;


-- 4.7 Seller performance ranking: who causes the most dissatisfaction?
SELECT
    seller_state,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery,
    ROUND(AVG(handling_days)::numeric, 1) AS avg_handling,
    ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN delivery_days IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS late_pct
FROM vw_orders_analysis
WHERE review_score IS NOT NULL
GROUP BY seller_state
HAVING COUNT(DISTINCT order_id) >= 50
ORDER BY avg_review ASC
LIMIT 15;
