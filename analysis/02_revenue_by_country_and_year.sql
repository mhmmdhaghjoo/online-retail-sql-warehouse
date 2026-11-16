-- Revenue by country and year with subtotals and a grand total in one pass.
SELECT COALESCE(c.country, CASE WHEN GROUPING(c.country) = 1 THEN 'ALL' ELSE 'n/a' END) AS country,
       COALESCE(d.year::text, 'ALL') AS year,
       COUNT(DISTINCT f.order_id)    AS orders,
       SUM(f.net_revenue)            AS net_revenue
FROM dw.fact_sales AS f
JOIN dw.dim_customer AS c USING (customer_key)
JOIN dw.dim_date AS d USING (date_key)
GROUP BY ROLLUP (c.country, d.year)
ORDER BY GROUPING(c.country), c.country NULLS LAST, GROUPING(d.year), d.year;
