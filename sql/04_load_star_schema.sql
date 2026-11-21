-- 04_load_star_schema.sql
-- Clean and load. Each cleaning rule answers one row of staging.dq_report.

BEGIN;

-- Dates: one row per calendar day covering the whole order history.
INSERT INTO dw.dim_date
SELECT TO_CHAR(d, 'YYYYMMDD')::integer,
       d::date,
       EXTRACT(year FROM d),
       EXTRACT(quarter FROM d),
       EXTRACT(month FROM d),
       DATE_TRUNC('month', d)::date,
       TO_CHAR(d, 'FMMonth'),
       EXTRACT(week FROM d),
       EXTRACT(isodow FROM d),
       EXTRACT(isodow FROM d) IN (6, 7)
FROM GENERATE_SERIES(
         (SELECT DATE_TRUNC('year', MIN(order_ts)) FROM staging.order_lines),
         (SELECT DATE_TRUNC('year', MAX(order_ts)) + INTERVAL '1 year - 1 day' FROM staging.order_lines),
         INTERVAL '1 day'
     ) AS d;

-- Customers. Rule: trim and upper-case the country; anything that still is
-- not a two-letter code becomes NULL. Rule: birth_year 1900 is a placeholder.
INSERT INTO dw.dim_customer (customer_id, signup_date, country, acquisition_channel, birth_year)
SELECT customer_id,
       signup_date,
       CASE WHEN UPPER(TRIM(country)) ~ '^[A-Z]{2}$' THEN UPPER(TRIM(country)) END,
       acquisition_channel,
       NULLIF(birth_year, 1900)
FROM staging.customers
ORDER BY customer_id;

-- "Unknown" member, so order lines without a customer keep their revenue
-- instead of being dropped by an inner join.
INSERT INTO dw.dim_customer (customer_id, signup_date, country, acquisition_channel, birth_year)
VALUES (NULL, NULL, NULL, 'unknown', NULL);

-- Products. Rule: one spelling per category.
INSERT INTO dw.dim_product (product_id, product_name, category, list_price, unit_cost)
SELECT product_id, product_name, INITCAP(category), unit_price, unit_cost
FROM staging.products
ORDER BY product_id;

-- Facts.
--   * exact duplicates (double export)  -> SELECT DISTINCT
--   * quantity = 0 (cancelled line)     -> excluded
--   * quantity < 0 (sign error)         -> absolute value
--   * customer_id is null               -> taken from the other lines of the
--                                          same order; "unknown" customer only
--                                          if no line of the order has one
--   (an order belongs to one customer, so a key lost on one line must not
--    split the order in two; 06_tests.sql checks the order grain)
WITH deduplicated AS (
    SELECT DISTINCT order_id, order_ts, customer_id, product_id, quantity, unit_price, discount_pct
    FROM staging.order_lines
    WHERE quantity <> 0
),
order_customer AS (
    SELECT order_id, MIN(customer_id) AS customer_id
    FROM deduplicated
    WHERE customer_id IS NOT NULL
    GROUP BY order_id
)
INSERT INTO dw.fact_sales
    (order_id, order_ts, date_key, customer_key, product_key,
     quantity, unit_price, discount_pct, net_revenue, cost)
SELECT o.order_id,
       o.order_ts,
       TO_CHAR(o.order_ts, 'YYYYMMDD')::integer,
       COALESCE(c.customer_key, unknown.customer_key),
       p.product_key,
       ABS(o.quantity),
       o.unit_price,
       o.discount_pct,
       ROUND(ABS(o.quantity) * o.unit_price * (1 - o.discount_pct), 2),
       ROUND(ABS(o.quantity) * p.unit_cost, 2)
FROM deduplicated AS o
JOIN dw.dim_product AS p USING (product_id)
LEFT JOIN order_customer AS oc USING (order_id)
LEFT JOIN dw.dim_customer AS c ON c.customer_id = COALESCE(o.customer_id, oc.customer_id)
CROSS JOIN (SELECT customer_key FROM dw.dim_customer WHERE customer_id IS NULL) AS unknown
ORDER BY o.order_ts, o.order_id;

COMMIT;

-- Indexes on the join and filter columns the marts use (see 07 for the effect).
CREATE INDEX idx_fact_sales_date     ON dw.fact_sales (date_key);
CREATE INDEX idx_fact_sales_customer ON dw.fact_sales (customer_key);
CREATE INDEX idx_fact_sales_product  ON dw.fact_sales (product_key);

ANALYZE dw.dim_date;
ANALYZE dw.dim_customer;
ANALYZE dw.dim_product;
ANALYZE dw.fact_sales;
