# Olist E-Commerce — Data Dictionary

## Source Tables (Raw)

### orders
| Column | Type | Description |
|---|---|---|
| order_id | VARCHAR (PK) | Unique order identifier |
| customer_id | VARCHAR (FK) | Links to customers table |
| order_status | VARCHAR | delivered, shipped, canceled, unavailable, invoiced, processing, created, approved |
| order_purchase_timestamp | TIMESTAMP | When the customer placed the order |
| order_approved_at | TIMESTAMP | When payment was approved (NULL for 160 orders) |
| order_delivered_carrier_date | TIMESTAMP | When the seller handed the order to the carrier |
| order_delivered_customer_date | TIMESTAMP | Actual delivery date to the customer |
| order_estimated_delivery_date | TIMESTAMP | Estimated delivery date shown to the customer at purchase |

### order_items
| Column | Type | Description |
|---|---|---|
| order_id | VARCHAR (FK) | Links to orders table |
| order_item_id | INTEGER | Sequential item number within the order (1, 2, 3…) |
| product_id | VARCHAR (FK) | Links to products table |
| seller_id | VARCHAR (FK) | Links to sellers table |
| shipping_limit_date | TIMESTAMP | Deadline for the seller to ship the item |
| price | DECIMAL | Item price in BRL (Brazilian Real) |
| freight_value | DECIMAL | Shipping cost for this item in BRL |

### customers
| Column | Type | Description |
|---|---|---|
| customer_id | VARCHAR (PK) | Unique customer ID per order (links to orders) |
| customer_unique_id | VARCHAR | De-duplicated customer identifier across orders |
| customer_zip_code_prefix | INTEGER | First 5 digits of customer zip code |
| customer_city | VARCHAR | Customer city name |
| customer_state | VARCHAR | Customer state abbreviation (e.g., SP, RJ, MG) |

### payments
| Column | Type | Description |
|---|---|---|
| order_id | VARCHAR (FK) | Links to orders table |
| payment_sequential | INTEGER | Sequential payment number if order paid in multiple methods |
| payment_type | VARCHAR | credit_card, boleto, voucher, debit_card, not_defined |
| payment_installments | INTEGER | Number of installments chosen (1–24) |
| payment_value | DECIMAL | Payment amount in BRL |

### reviews
| Column | Type | Description |
|---|---|---|
| review_id | VARCHAR | Review identifier (NOT unique — 814 duplicates in raw data) |
| order_id | VARCHAR (FK) | Links to orders table |
| review_score | INTEGER | Customer rating 1–5 (5 = best) |
| review_comment_title | VARCHAR | Optional review title (NULL for 88% of reviews) |
| review_comment_message | VARCHAR | Optional review text in Portuguese (NULL for 59%) |
| review_creation_date | TIMESTAMP | When the review survey was sent |
| review_answer_timestamp | TIMESTAMP | When the customer submitted the review |

### products
| Column | Type | Description |
|---|---|---|
| product_id | VARCHAR (PK) | Unique product identifier |
| product_category_name | VARCHAR | Category in Portuguese (NULL for 610 products) |
| product_name_lenght | INTEGER | Character count of the product name (note: typo in source) |
| product_description_lenght | INTEGER | Character count of the description (note: typo in source) |
| product_photos_qty | INTEGER | Number of product photos |
| product_weight_g | INTEGER | Product weight in grams |
| product_length_cm | INTEGER | Product length in centimeters |
| product_height_cm | INTEGER | Product height in centimeters |
| product_width_cm | INTEGER | Product width in centimeters |

### sellers
| Column | Type | Description |
|---|---|---|
| seller_id | VARCHAR (PK) | Unique seller identifier |
| seller_zip_code_prefix | INTEGER | First 5 digits of seller zip code |
| seller_city | VARCHAR | Seller city name |
| seller_state | VARCHAR | Seller state abbreviation |

### category_translation
| Column | Type | Description |
|---|---|---|
| product_category_name | VARCHAR (PK) | Category name in Portuguese |
| product_category_name_english | VARCHAR | Category name in English |

### geolocation
| Column | Type | Description |
|---|---|---|
| geolocation_zip_code_prefix | INTEGER | Zip code prefix |
| geolocation_lat | DECIMAL | Latitude |
| geolocation_lng | DECIMAL | Longitude |
| geolocation_city | VARCHAR | City name |
| geolocation_state | VARCHAR | State abbreviation |

---

## Cleaned / Derived Tables

### orders_clean
All columns from `orders` plus:

| Column | Type | Description |
|---|---|---|
| order_month | TIMESTAMP | Truncated to first of month |
| order_year | INTEGER | Year extracted from purchase timestamp |
| order_quarter | INTEGER | Quarter (1–4) extracted from purchase timestamp |
| order_day_of_week | INTEGER | Day of week (0 = Sunday, 6 = Saturday) |
| delivery_days | DECIMAL | Days from purchase to delivery (delivered orders only) |
| delay_days | DECIMAL | Days past estimated delivery (negative = early). NULL for non-delivered. |
| is_late | BOOLEAN | TRUE if delivered after estimated date |
| approval_hours | DECIMAL | Hours from purchase to payment approval |

### reviews_clean
Same columns as `reviews`, deduplicated to one row per `order_id` (most recent review kept).

### products_clean
| Column | Type | Description |
|---|---|---|
| product_id | VARCHAR (PK) | Same as source |
| product_category_name | VARCHAR | Portuguese name; 'unknown' replaces NULLs |
| product_category_english | VARCHAR | English name from translation table |
| product_name_length | INTEGER | Renamed from source typo |
| product_description_length | INTEGER | Renamed from source typo |
| product_photos_qty | INTEGER | Same as source |
| product_weight_g | INTEGER | Same as source (2 NULLs remain) |
| product_length_cm | INTEGER | Same as source |
| product_height_cm | INTEGER | Same as source |
| product_width_cm | INTEGER | Same as source |

### payments_clean
All columns from `payments` plus:

| Column | Type | Description |
|---|---|---|
| is_anomaly | BOOLEAN | TRUE for zero-value payments and 'not_defined' types |

### geolocation_clean
| Column | Type | Description |
|---|---|---|
| geolocation_zip_code_prefix | INTEGER (PK) | Zip code prefix |
| avg_lat | DECIMAL | Mean latitude across all points for this prefix |
| avg_lng | DECIMAL | Mean longitude across all points for this prefix |
| city | VARCHAR | Most frequent city name for this prefix |
| state | VARCHAR | Most frequent state for this prefix |
| point_count | INTEGER | Number of raw geolocation points aggregated |

### orders_summary
One row per order (aggregated from items). Used for KPI dashboards.

| Column | Type | Description |
|---|---|---|
| order_id | VARCHAR (PK) | Unique order identifier |
| order_status | VARCHAR | From orders_clean |
| order_purchase_timestamp | TIMESTAMP | From orders_clean |
| order_month | TIMESTAMP | From orders_clean |
| order_year / quarter / day_of_week | INTEGER | From orders_clean |
| delivery_days | DECIMAL | From orders_clean |
| delay_days | DECIMAL | From orders_clean |
| is_late | BOOLEAN | From orders_clean |
| customer_unique_id | VARCHAR | From customers |
| customer_state | VARCHAR | From customers |
| item_count | INTEGER | Number of items in the order |
| order_revenue | DECIMAL | SUM of item prices (BRL) |
| order_freight | DECIMAL | SUM of freight values (BRL) |
| order_total | DECIMAL | Revenue + freight |
| primary_payment_type | VARCHAR | Payment type with the highest value |
| total_installments | INTEGER | Max installments used |
| total_payment_value | DECIMAL | Total paid across all payment methods |
| review_score | INTEGER | Customer rating 1–5 |

### vw_orders_analysis
Denormalized view joining all cleaned tables at the item level. Filtered to Jan 2017 – Aug 2018. Contains all columns needed for the four analysis categories.

---

## Key Relationships

```
customers (customer_id) ──── orders (customer_id)
                                │
                                ├── order_items (order_id)
                                │       ├── products (product_id)
                                │       └── sellers (seller_id)
                                │
                                ├── payments (order_id)
                                └── reviews (order_id)

geolocation (zip_code_prefix) ── customers / sellers (zip_code_prefix)
category_translation (product_category_name) ── products (product_category_name)
```

---

## Analysis Date Range

**Jan 2017 – Aug 2018** (20 complete months). Boundary months with <25 orders excluded.
