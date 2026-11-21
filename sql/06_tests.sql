-- 06_tests.sql
-- Assertions on the loaded warehouse. Any failure raises an exception, and
-- because run.sh uses ON_ERROR_STOP the whole build fails with it.

DO $$
DECLARE
    staged_lines   bigint;
    expected_lines bigint;
    loaded_lines   bigint;
    n              bigint;
    staged_revenue numeric;
    loaded_revenue numeric;
BEGIN
    -- 1. Row reconciliation: staging minus the documented exclusions = fact.
    SELECT COUNT(*) INTO staged_lines FROM staging.order_lines;
    SELECT COUNT(*) INTO expected_lines
    FROM (SELECT DISTINCT * FROM staging.order_lines WHERE quantity <> 0) AS s;
    SELECT COUNT(*) INTO loaded_lines FROM dw.fact_sales;
    IF loaded_lines <> expected_lines THEN
        RAISE EXCEPTION 'row reconciliation failed: expected %, loaded %', expected_lines, loaded_lines;
    END IF;

    -- 2. Revenue reconciliation, computed independently from the raw rows.
    SELECT SUM(ROUND(ABS(quantity) * unit_price * (1 - discount_pct), 2)) INTO staged_revenue
    FROM (SELECT DISTINCT * FROM staging.order_lines WHERE quantity <> 0) AS s;
    SELECT SUM(net_revenue) INTO loaded_revenue FROM dw.fact_sales;
    IF staged_revenue <> loaded_revenue THEN
        RAISE EXCEPTION 'revenue reconciliation failed: % vs %', staged_revenue, loaded_revenue;
    END IF;

    -- 3. Exactly one "unknown" customer.
    SELECT COUNT(*) INTO n FROM dw.dim_customer WHERE customer_id IS NULL;
    IF n <> 1 THEN RAISE EXCEPTION 'expected 1 unknown customer, found %', n; END IF;

    -- 4. Categories are normalised: no two spellings of the same name.
    SELECT COUNT(*) - COUNT(DISTINCT LOWER(category)) INTO n
    FROM (SELECT DISTINCT category FROM dw.dim_product) AS c;
    IF n <> 0 THEN RAISE EXCEPTION '% category spelling variants left', n; END IF;

    -- 5. The date dimension has no gaps.
    SELECT (MAX(full_date) - MIN(full_date) + 1) - COUNT(*) INTO n FROM dw.dim_date;
    IF n <> 0 THEN RAISE EXCEPTION 'dim_date has % missing days', n; END IF;

    -- 6. Marts agree with the fact table.
    SELECT COUNT(*) INTO n
    FROM (SELECT SUM(net_revenue) AS r FROM marts.monthly_revenue) AS m
    WHERE m.r <> loaded_revenue;
    IF n <> 0 THEN RAISE EXCEPTION 'monthly_revenue does not sum to fact revenue'; END IF;

    -- 7. Retention starts at 100 % and never exceeds it.
    SELECT COUNT(*) INTO n FROM marts.cohort_retention
    WHERE (months_since_first = 0 AND retention_pct <> 100) OR retention_pct > 100;
    IF n <> 0 THEN RAISE EXCEPTION '% impossible retention values', n; END IF;

    -- 8. Every known customer with an order has exactly one RFM row.
    SELECT COUNT(*) - COUNT(DISTINCT customer_key) INTO n FROM marts.customer_rfm;
    IF n <> 0 THEN RAISE EXCEPTION 'customer_rfm has % duplicate customers', n; END IF;

    -- 9. No order carries two different customer IDs in the raw export
    --    (the back-fill in 04 would otherwise pick one silently).
    SELECT COUNT(*) INTO n FROM (
        SELECT order_id FROM staging.order_lines
        WHERE customer_id IS NOT NULL
        GROUP BY order_id HAVING COUNT(DISTINCT customer_id) > 1
    ) AS conflicts;
    IF n <> 0 THEN RAISE EXCEPTION '% orders have conflicting customer IDs', n; END IF;

    -- 10. marts.orders really is one row per order.
    SELECT COUNT(*) - COUNT(DISTINCT order_id) INTO n FROM marts.orders;
    IF n <> 0 THEN RAISE EXCEPTION 'marts.orders has % duplicate orders', n; END IF;

    RAISE NOTICE 'all 10 warehouse tests passed (% staged lines -> % fact rows)', staged_lines, loaded_lines;
END $$;
