-- Parts:
--   1 - Exploration
--   2 - Star Schema
--   3 - Load
--   4 - Validation
--   5 - Business Queries
--
-- Database: SQLite
--
-- IMPORTANT:
-- Grain of FACT_ORDERS = 1 row per order
--
-- Main business questions:
--   - Are customers acquired in 2017 still buying in 2018?
--   - What is customer retention by cohort?
--   - What is customer lifetime revenue / CLV?
--   - Who are the top 1% power users?
--   - Does delivery time relate to review score?


-- PART 1: EXPLORATION

-- 1.1 ORDERS
-- Date range and order status distribution

SELECT
    COUNT(*) AS total_orders,
    MIN(order_purchase_timestamp) AS first_purchase,
    MAX(order_purchase_timestamp) AS last_purchase
FROM olist_orders_dataset;


SELECT
    order_status,
    COUNT(*) AS n_orders
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY n_orders DESC; 
    
------------------------------------------------------------------------

-- 1.2 CUSTOMERS
-- customer_id vs customer_unique_id
--
-- customer_id:
--   Anonymous identifier associated with an order/customer record.
--
-- customer_unique_id:
--   Business-level customer identifier used for retention/cohort analysis.

------------------------------------------------------------------------

SELECT
    COUNT(DISTINCT customer_id) AS customer_ids,
    COUNT(DISTINCT customer_unique_id) AS real_customers
FROM olist_customers_dataset;

------------------------------------------------------------------------

-- 1.3 REPEAT BUYERS
-- Customers with more than one order

------------------------------------------------------------------------

SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS n_orders
FROM olist_customers_dataset c 
JOIN olist_orders_dataset o
    ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
HAVING COUNT(DISTINCT o.order_id) > 1
ORDER BY n_orders DESC
LIMIT 20;

------------------------------------------------------------------------

-- 1.4 PAYMENTS
-- REVENUE BY PAYMENT TYPE

------------------------------------------------------------------------

SELECT
    payment_type,
    COUNT(*) AS n_payment_rows,
    ROUND(SUM(payment_value), 2) AS total_revenue
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY total_revenue DESC;


-- -----------------------------------------------------------------------------
-- 1.5 REVIEWS
-- Review score distribution
-- -----------------------------------------------------------------------------

SELECT
    review_score,
    COUNT(*) AS n_reviews
FROM olist_order_reviews_dataset
GROUP BY review_score
ORDER BY review_score;

-- -----------------------------------------------------------------------------
-- 1.6 DELIVERY
-- Average delivery time for delivered orders
-- -----------------------------------------------------------------------------

SELECT
    ROUND(
        AVG(
            JULIANDAY(order_delivered_customer_date)
            - JULIANDAY(order_purchase_timestamp)
        ),
        2
    ) AS avg_delivery_days,

    COUNT(
        CASE
            WHEN order_delivered_customer_date IS NULL THEN 1
        END
    ) AS undelivered_orders

FROM olist_orders_dataset
WHERE order_status = 'delivered';


-- -----------------------------------------------------------------------------
-- PART 2: STAR SCHEMA
-- -----------------------------------------------------------------------------

-- 2.1 DIM_CUSTOMERS

DROP TABLE IF EXISTS dim_customers;

CREATE TABLE dim_customers (
    customer_key        INTEGER PRIMARY KEY,
    customer_unique_id  TEXT NOT NULL UNIQUE,
    customer_zip        TEXT,
    customer_city       TEXT,
    customer_state      TEXT
);

-- 2.2 DIM_DATE

DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
    date_key    TEXT PRIMARY KEY,
    year        INTEGER,
    quarter     INTEGER,
    month       INTEGER,
    month_name  TEXT,
    week        INTEGER,
    day_of_week TEXT       
);

-- 2.3 DIM_PAYMENT_TYPE

DROP TABLE IF EXISTS dim_payment_type;

CREATE TABLE dim_payment_type (
    payment_type_key    INTEGER PRIMARY KEY,
    payment_type        TEXT NOT NULL UNIQUE
);

-- 2.4 FACT_ORDERS
-- GRAIN = one row per order
-- Revenue is aggregated from the payment table before loading this fact.
-- This prevents payment rows from multiplying order rows.

DROP TABLE IF EXISTS fact_orders;

CREATE TABLE fact_orders (
    order_id                        TEXT PRIMARY KEY,

    customer_key                    INTEGER NOT NULL
                                    REFERENCES dim_customers(customer_key),

    payment_type_key                INTEGER
                                    REFERENCES dim_payment_type(payment_type_key),

    purchase_date_key               TEXT
                                    REFERENCES dim_date(date_key),

    order_status                    TEXT,

    total_revenue                   REAL,

    order_purchase_timestamp        TEXT,

    order_delivered_customer_date   TEXT,

    order_estimated_delivery_date   TEXT,

    actual_delivery_days            REAL,

    delivery_delay_days             REAL

);


-- -----------------------------------------------------------------------------
-- 2.5 FACT_REVIEWS
-- One row per review.
-- An order may have multiple review records, so we aggregate reviews
-- whenever we join them to FACT_ORDERS for business analytics.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS fact_reviews;

CREATE TABLE fact_reviews (
    review_id     TEXT PRIMARY KEY,
    order_id      TEXT REFERENCES fact_orders(order_id),
    review_score  INTEGER  
);

-- -----------------------------------------------------------------------------
-- PART 3 : LOAD DATA
-- -----------------------------------------------------------------------------

-- 3.1 LOAD CUSTOMER DIMENSION

INSERT OR IGNORE INTO dim_customers (
    customer_unique_id,
    customer_zip,
    customer_city,
    customer_state
)
SELECT DISTINCT
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM olist_customers_dataset
WHERE customer_unique_id IS NOT NULL;


-- 3.2 LOAD PAYMENT TYPE DIMENSION

INSERT OR IGNORE INTO dim_payment_type (
    payment_type
)
SELECT DISTINCT
    payment_type
FROM olist_order_payments_dataset
WHERE payment_type IS NOT NULL;

-- 3.3 LOAD DATE DIMENSION

INSERT OR IGNORE INTO dim_date (
    date_key,
    year,
    quarter,
    month,
    month_name,
    week,
    day_of_week
)
SELECT DISTINCT

    DATE(order_purchase_timestamp) AS date_key,

    CAST(
        STRFTIME('%Y', order_purchase_timestamp)
        AS INTEGER
    ) AS year,

    (
        (
            CAST(
                STRFTIME('%m', order_purchase_timestamp)
                AS INTEGER
            ) - 1
        ) / 3
    ) + 1 AS quarter,

    CAST(
        STRFTIME('%m', order_purchase_timestamp)
        AS INTEGER
    ) AS month,

    CASE
        CAST(
            STRFTIME('%m', order_purchase_timestamp)
            AS INTEGER
        )
        WHEN 1  THEN 'January'
        WHEN 2  THEN 'February'
        WHEN 3  THEN 'March'
        WHEN 4  THEN 'April'
        WHEN 5  THEN 'May'
        WHEN 6  THEN 'June'
        WHEN 7  THEN 'July'
        WHEN 8  THEN 'August'
        WHEN 9  THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
    END AS month_name,

    CAST(
        STRFTIME('%W', order_purchase_timestamp)
        AS INTEGER
    ) AS week,

    CASE
        CAST(
            STRFTIME('%w', order_purchase_timestamp)
            AS INTEGER
        )
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_of_week

FROM olist_orders_dataset

WHERE order_purchase_timestamp IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 3.4 PREPARE PAYMENT AGGREGATION
-- -----------------------------------------------------------------------------

DROP VIEW IF EXISTS v_payment_agg;

CREATE VIEW v_payment_agg AS

SELECT
    order_id,
    SUM(payment_value)  AS total_revenue,
    COUNT(*)            AS payment_count
FROM olist_order_payments_dataset
GROUP BY order_id;


-- -----------------------------------------------------------------------------
-- 3.5 PREPARE MAIN PAYMENT TYPE
-- -----------------------------------------------------------------------------

DROP VIEW IF EXISTS v_order_payment_type;

CREATE VIEW v_order_payment_type AS

SELECT
    p.order_id,
    p.payment_type

FROM olist_order_payments_dataset p

JOIN (
    SELECT
        order_id,
        MAX(payment_value) AS max_payment_value
    FROM olist_order_payments_dataset
    GROUP BY order_id
) m

ON  p.order_id      = m.order_id
AND p.payment_value = m.max_payment_value

GROUP BY
    p.order_id,
    p.payment_type;


-- -----------------------------------------------------------------------------
-- 3.6 LOAD FACT_ORDERS
-- -----------------------------------------------------------------------------

INSERT OR IGNORE INTO fact_orders (
    order_id,
    customer_key,
    payment_type_key,
    purchase_date_key,
    order_status,
    total_revenue,
    order_purchase_timestamp,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    actual_delivery_days,
    delivery_delay_days
)

SELECT

    o.order_id,

    dc.customer_key,

    dpt.payment_type_key,

    DATE(o.order_purchase_timestamp) AS purchase_date_key,

    o.order_status,

    pa.total_revenue,

    o.order_purchase_timestamp,

    o.order_delivered_customer_date,

    o.order_estimated_delivery_date,

    
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN ROUND(
            JULIANDAY(o.order_delivered_customer_date)
            - JULIANDAY(o.order_purchase_timestamp),
            2
        )
        ELSE NULL
    END AS actual_delivery_days,


    CASE
        WHEN o.order_delivered_customer_date  IS NOT NULL
         AND o.order_estimated_delivery_date  IS NOT NULL
        THEN ROUND(
            JULIANDAY(o.order_delivered_customer_date)
            - JULIANDAY(o.order_estimated_delivery_date),
            2
        )
        ELSE NULL
    END AS delivery_delay_days

FROM olist_orders_dataset o

JOIN olist_customers_dataset c
    ON c.customer_id = o.customer_id

JOIN dim_customers dc
    ON dc.customer_unique_id = c.customer_unique_id

LEFT JOIN v_payment_agg pa
    ON pa.order_id = o.order_id

LEFT JOIN v_order_payment_type opt
    ON opt.order_id = o.order_id

LEFT JOIN dim_payment_type dpt
    ON dpt.payment_type = opt.payment_type;


-- -----------------------------------------------------------------------------
-- 3.7 LOAD FACT_REVIEWS
-- -----------------------------------------------------------------------------

INSERT OR IGNORE INTO fact_reviews (
    review_id,
    order_id,
    review_score
)

SELECT
    review_id,
    order_id,
    review_score

FROM olist_order_reviews_dataset

WHERE review_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- PART 4 : VALIDATION
-- -----------------------------------------------------------------------------

-- 4.1 ROW COUNTS

SELECT
    'dim_customers' AS table_name,
    COUNT(*) AS row_count
FROM dim_customers

UNION ALL

SELECT
    'dim_date',
    COUNT(*)
FROM dim_date

UNION ALL

SELECT
    'fact_reviews',
    COUNT(*)
FROM fact_reviews;

-- -----------------------------------------------------------------------------
-- 4.2 FACT ORDERS NULL CHECK
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*) AS total_fact_orders,

    COUNT(
        CASE
            WHEN customer_key IS NULL THEN 1
        END
    ) AS null_customer_key,

    COUNT(
        CASE
            WHEN purchase_date_key IS NULL THEN 1
        END
    ) AS null_purchase_date

FROM fact_orders;

-- -----------------------------------------------------------------------------
-- 4.3 ORPHAN CUSTOMER CHECK
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*) AS orphan_orders

FROM fact_orders f

LEFT JOIN dim_customers d
    ON d.customer_key = f.customer_key

WHERE d.customer_key IS NULL;


-- -----------------------------------------------------------------------------
-- 4.4 ORPHAN DATE CHECK
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*) AS orphan_dates

FROM fact_orders f

LEFT JOIN dim_date d
    ON d.date_key = f.purchase_date_key

WHERE d.date_key IS NULL;

-- -----------------------------------------------------------------------------
-- 4.5 DUPLICATE ORDER CHECK
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*) AS duplicate_orders

FROM (
    SELECT
        order_id
    FROM fact_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
);

-- -----------------------------------------------------------------------------
-- 4.6 REVENUE VALIDATION
-- -----------------------------------------------------------------------------

SELECT
    ROUND(SUM(payment_value), 2) AS raw_payment_revenue,

    (
        SELECT ROUND(SUM(total_revenue), 2)
        FROM fact_orders
    ) AS warehouse_revenue

FROM olist_order_payments_dataset;

-- -----------------------------------------------------------------------------
-- 4.7 ORDER COUNT VALIDATION
-- -----------------------------------------------------------------------------

SELECT
    (
        SELECT COUNT(DISTINCT order_id)
        FROM olist_orders_dataset
    ) AS raw_orders,

    (
        SELECT COUNT(*)
        FROM fact_orders
    ) AS warehouse_orders;


-- =============================================================================
-- PART 5 : BUSINESS QUERIES
-- =============================================================================

-- 5.1 CUSTOMER COHORT

-- Definition : cohort = month of customer's first valid purchase
-- Customer identity : customer_unique_id

-- -----------------------------------------------------------------------------


DROP VIEW IF EXISTS v_customer_cohort;

CREATE VIEW v_customer_cohort AS

SELECT

    dc.customer_unique_id,

    MIN(
        DATE(
            fo.order_purchase_timestamp,
            'start of month'
        )
    ) AS cohort_month

FROM fact_orders fo

JOIN dim_customers dc
    ON dc.customer_key = fo.customer_key

WHERE fo.order_status IN (
    'delivered',
    'shipped',
    'invoiced'
)

GROUP BY
    dc.customer_unique_id;

-- -----------------------------------------------------------------------------
-- 5.2 COHORT SIZE
-- Number of customers acquired in each month
-- -----------------------------------------------------------------------------

SELECT

    cohort_month,

    COUNT(DISTINCT customer_unique_id) AS cohort_size

FROM v_customer_cohort

GROUP BY cohort_month

ORDER BY cohort_month;

-- -----------------------------------------------------------------------------
-- 5.3 ORDERS WITH COHORT INFORMATION
--
-- month_number:
--     0  = first purchase month
--     1  = one month later
--     ...
--     12 = one year later
-- -----------------------------------------------------------------------------

DROP VIEW IF EXISTS v_orders_with_cohort;

CREATE VIEW v_orders_with_cohort AS

SELECT

    fo.order_id,

    dc.customer_unique_id,

    vc.cohort_month,

    DATE(
        fo.order_purchase_timestamp,
        'start of month'
    ) AS purchase_month,

    (
        (
            CAST(
                STRFTIME('%Y', fo.order_purchase_timestamp)
                AS INTEGER
            )
            -
            CAST(
                STRFTIME('%Y', vc.cohort_month)
                AS INTEGER
            )
        ) * 12

        +

        (
            CAST(
                STRFTIME('%m', fo.order_purchase_timestamp)
                AS INTEGER
            )
            -
            CAST(
                STRFTIME('%m', vc.cohort_month)
                AS INTEGER
            )
        )
    ) AS month_number,

    fo.total_revenue

FROM fact_orders fo

JOIN dim_customers dc
    ON dc.customer_key = fo.customer_key

JOIN v_customer_cohort vc
    ON vc.customer_unique_id = dc.customer_unique_id

WHERE fo.order_status IN (
    'delivered',
    'shipped',
    'invoiced'
);

-- -----------------------------------------------------------------------------
-- 5.4 COHORT RETENTION RAW
--
-- Output:
--     cohort_month
--     month_number
--     retained_customers
-- -----------------------------------------------------------------------------

SELECT

    cohort_month,

    month_number,

    COUNT(DISTINCT customer_unique_id) AS retained_customers

FROM v_orders_with_cohort

GROUP BY
    cohort_month,
    month_number;

-- -----------------------------------------------------------------------------
-- 5.5 COHORT RETENTION RATE
--
-- Retention rate = retained_customers / cohort_size × 100
-- -----------------------------------------------------------------------------

WITH cohort_size AS (

    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM v_customer_cohort
    GROUP BY cohort_month

),

retention AS (

    SELECT
        cohort_month,
        month_number,
        COUNT(DISTINCT customer_unique_id) AS retained_customers
    FROM v_orders_with_cohort
    GROUP BY
        cohort_month,
        month_number

)

SELECT

    r.cohort_month,

    r.month_number,

    c.cohort_size,

    r.retained_customers,

    ROUND(
        100.0 * r.retained_customers / c.cohort_size,
        2
    ) AS retention_rate_percent

FROM retention r

JOIN cohort_size c
    ON c.cohort_month = r.cohort_month

ORDER BY
    r.cohort_month,
    r.month_number;

-- -----------------------------------------------------------------------------
-- 5.6 2017 CUSTOMERS — DID THEY BUY IN 2018?
-- CEO'S MAIN QUESTION
-- -----------------------------------------------------------------------------

WITH customer_first_purchase AS (

    SELECT

        dc.customer_unique_id,

        MIN(DATE(fo.order_purchase_timestamp)) AS first_purchase_date

    FROM fact_orders fo

    JOIN dim_customers dc
        ON dc.customer_key = fo.customer_key

    WHERE fo.order_status IN (
        'delivered',
        'shipped',
        'invoiced'
    )

    GROUP BY
        dc.customer_unique_id

),

customers_2017 AS (

    SELECT customer_unique_id

    FROM customer_first_purchase

    WHERE first_purchase_date >= '2017-01-01'
      AND first_purchase_date <  '2018-01-01'

),

returned_2018 AS (

    SELECT DISTINCT
        c.customer_unique_id

    FROM customers_2017 c

    JOIN dim_customers dc
        ON dc.customer_unique_id = c.customer_unique_id

    JOIN fact_orders fo
        ON fo.customer_key = dc.customer_key

    WHERE fo.order_status IN (
        'delivered',
        'shipped',
        'invoiced'
    )

    AND DATE(fo.order_purchase_timestamp) >= '2018-01-01'

)

SELECT

    (
        SELECT COUNT(*)
        FROM returned_2018
    ) AS customers_returned_2018,

    ROUND(
        100.0
        *
        (SELECT COUNT(*) FROM returned_2018)
        /
        NULLIF(
            (SELECT COUNT(*) FROM customers_2017),
            0
        ),
        2
    ) AS retention_2018_percent;

-- -----------------------------------------------------------------------------
-- 5.7 CUSTOMER LIFETIME VALUE (CLV)
-- CLV = total historical revenue generated by customer
-- -----------------------------------------------------------------------------

DROP VIEW IF EXISTS v_customer_clv;

CREATE VIEW v_customer_clv AS

SELECT

    dc.customer_unique_id,

    SUM(fo.total_revenue)           AS lifetime_revenue,

    COUNT(fo.order_id)              AS total_orders,

    ROUND(AVG(fo.total_revenue), 2) AS average_order_value

FROM fact_orders fo

JOIN dim_customers dc
    ON dc.customer_key = fo.customer_key

WHERE fo.order_status IN (
    'delivered',
    'shipped',
    'invoiced'
)

GROUP BY
    dc.customer_unique_id;

-- View CLV ranking

SELECT *
FROM v_customer_clv
ORDER BY lifetime_revenue DESC;

-- -----------------------------------------------------------------------------
-- 5.8 POWER USERS
-- Power Users = top 1% of customers by lifetime revenue.
-- -----------------------------------------------------------------------------

WITH ranked_customers AS (

    SELECT

        customer_unique_id,

        lifetime_revenue,

        total_orders,

        average_order_value,

        NTILE(100) OVER (
            ORDER BY lifetime_revenue DESC
        ) AS revenue_percentile

    FROM v_customer_clv

)

SELECT

    customer_unique_id,

    lifetime_revenue,

    total_orders,

    average_order_value

FROM ranked_customers

WHERE revenue_percentile = 1

ORDER BY lifetime_revenue DESC;

-- -----------------------------------------------------------------------------
-- 5.9 MONTHLY REVENUE TREND
-- -----------------------------------------------------------------------------

SELECT

    dd.year,

    dd.month,

    dd.month_name,

    COUNT(fo.order_id) AS n_orders,

    ROUND(SUM(fo.total_revenue), 2) AS monthly_revenue

FROM fact_orders fo

JOIN dim_date dd
    ON dd.date_key = fo.purchase_date_key

WHERE fo.order_status IN (
    'delivered',
    'shipped',
    'invoiced'
)

GROUP BY
    dd.year,
    dd.month,
    dd.month_name

ORDER BY
    dd.year,
    dd.month;

-- -----------------------------------------------------------------------------
-- 5.10 DELIVERY TIME VS REVIEW SCORE — BY STATE
-- We aggregate reviews by order first.
-- -----------------------------------------------------------------------------

WITH review_by_order AS (

    SELECT
        order_id,
        AVG(review_score) AS avg_review_score
    FROM fact_reviews
    GROUP BY order_id

)

SELECT

    dc.customer_state,

    ROUND(AVG(fo.actual_delivery_days), 2) AS avg_delivery_days,


    ROUND(AVG(fo.delivery_delay_days), 2) AS avg_delay_days,

    ROUND(AVG(r.avg_review_score), 2) AS avg_review_score,

    COUNT(DISTINCT fo.order_id) AS delivered_orders

FROM fact_orders fo

JOIN dim_customers dc
    ON dc.customer_key = fo.customer_key

LEFT JOIN review_by_order r
    ON r.order_id = fo.order_id

WHERE fo.order_status = 'delivered'
  AND fo.actual_delivery_days > 0

GROUP BY
    dc.customer_state

ORDER BY
    avg_delivery_days DESC;

-- -----------------------------------------------------------------------------
-- 5.11 DELIVERY TIME VS REVIEW SCORE — OVERALL
-- Overall relationship before Python correlation analysis.
-- -----------------------------------------------------------------------------

WITH review_by_order AS (

    SELECT
        order_id,
        
        AVG(review_score) AS avg_review_score
    FROM fact_reviews
    GROUP BY order_id

)

SELECT

    ROUND(AVG(fo.actual_delivery_days), 2)  AS overall_avg_delivery_days,

    ROUND(AVG(r.avg_review_score), 2)       AS overall_avg_review_score,

    COUNT(DISTINCT fo.order_id)             AS delivered_orders_with_data

FROM fact_orders fo

JOIN review_by_order r
    ON r.order_id = fo.order_id

WHERE fo.order_status = 'delivered'

  AND fo.actual_delivery_days > 0

  AND r.avg_review_score IS NOT NULL;