-- Black Friday period (20-30 November) against the rest of that year:
-- daily revenue, average discount and margin.
SELECT d.year,
       CASE WHEN d.month = 11 AND EXTRACT(day FROM d.full_date) >= 20 THEN '20-30 Nov' ELSE 'rest of year' END AS period,
       COUNT(DISTINCT d.full_date)                                   AS days,
       ROUND(SUM(f.net_revenue) / COUNT(DISTINCT d.full_date), 2)    AS revenue_per_day,
       ROUND(100 * AVG(f.discount_pct), 1)                           AS avg_discount_pct,
       ROUND(100 * SUM(f.net_revenue - f.cost) / SUM(f.net_revenue), 1) AS margin_pct
FROM dw.fact_sales AS f
JOIN dw.dim_date AS d USING (date_key)
GROUP BY d.year, period
ORDER BY d.year, period;
