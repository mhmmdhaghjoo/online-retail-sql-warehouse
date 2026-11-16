-- 07_performance.sql
-- What the date index buys: the same one-week query planned without and
-- with it. The fact table is copied 40x first, because on the original
-- ~32k rows a sequential scan is cheap and the planner rightly prefers it.

DROP TABLE IF EXISTS dw.fact_sales_big;
CREATE TABLE dw.fact_sales_big AS
SELECT f.* FROM dw.fact_sales AS f CROSS JOIN GENERATE_SERIES(1, 40);
ANALYZE dw.fact_sales_big;

\echo '--- without index ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT SUM(net_revenue) FROM dw.fact_sales_big WHERE date_key BETWEEN 20251124 AND 20251130;

CREATE INDEX idx_fact_sales_big_date ON dw.fact_sales_big (date_key);
ANALYZE dw.fact_sales_big;

\echo '--- with B-tree index on date_key ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT SUM(net_revenue) FROM dw.fact_sales_big WHERE date_key BETWEEN 20251124 AND 20251130;

DROP TABLE dw.fact_sales_big;
