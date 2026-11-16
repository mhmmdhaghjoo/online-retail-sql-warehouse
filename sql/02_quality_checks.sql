-- 02_quality_checks.sql
-- Profile the raw data before anything is cleaned. Every check counts the
-- rows that violate one rule; the result is stored so the numbers can be
-- reported next to the cleaning rule that deals with them (see 04).

DROP TABLE IF EXISTS staging.dq_report;

CREATE TABLE staging.dq_report AS
WITH line_dupes AS (
    SELECT COUNT(*) - 1 AS extra_copies
    FROM staging.order_lines
    GROUP BY order_id, order_ts, customer_id, product_id, quantity, unit_price, discount_pct
    HAVING COUNT(*) > 1
)
SELECT 'order_lines' AS table_name, 'exact duplicate rows' AS check_name,
       COALESCE((SELECT SUM(extra_copies) FROM line_dupes), 0)::bigint AS failing_rows,
       (SELECT COUNT(*) FROM staging.order_lines) AS total_rows
UNION ALL
SELECT 'order_lines', 'customer_id is null',
       COUNT(*) FILTER (WHERE customer_id IS NULL), COUNT(*) FROM staging.order_lines
UNION ALL
SELECT 'order_lines', 'quantity = 0 (cancelled line)',
       COUNT(*) FILTER (WHERE quantity = 0), COUNT(*) FROM staging.order_lines
UNION ALL
SELECT 'order_lines', 'quantity < 0 (sign error)',
       COUNT(*) FILTER (WHERE quantity < 0), COUNT(*) FROM staging.order_lines
UNION ALL
SELECT 'order_lines', 'product_id not in products',
       COUNT(*) FILTER (WHERE p.product_id IS NULL), COUNT(*)
FROM staging.order_lines AS o
LEFT JOIN staging.products AS p USING (product_id)
UNION ALL
SELECT 'order_lines', 'order before customer sign-up',
       COUNT(*) FILTER (WHERE o.order_ts::date < c.signup_date), COUNT(*)
FROM staging.order_lines AS o
JOIN staging.customers AS c USING (customer_id)
UNION ALL
SELECT 'customers', 'duplicate customer_id',
       COUNT(*) - COUNT(DISTINCT customer_id), COUNT(*) FROM staging.customers
UNION ALL
SELECT 'customers', 'country is null',
       COUNT(*) FILTER (WHERE country IS NULL), COUNT(*) FROM staging.customers
UNION ALL
SELECT 'customers', 'country not a clean ISO code',
       COUNT(*) FILTER (WHERE country !~ '^[A-Z]{2}$'), COUNT(*) FROM staging.customers
UNION ALL
SELECT 'customers', 'birth_year placeholder (1900)',
       COUNT(*) FILTER (WHERE birth_year = 1900), COUNT(*) FROM staging.customers
UNION ALL
SELECT 'products', 'category spelling variants',
       COUNT(*) FILTER (WHERE category <> INITCAP(category)), COUNT(*) FROM staging.products
UNION ALL
SELECT 'products', 'unit_cost >= unit_price',
       COUNT(*) FILTER (WHERE unit_cost >= unit_price), COUNT(*) FROM staging.products;

SELECT table_name, check_name, failing_rows, total_rows,
       ROUND(100.0 * failing_rows / NULLIF(total_rows, 0), 2) AS pct_failing
FROM staging.dq_report
ORDER BY table_name, failing_rows DESC;
