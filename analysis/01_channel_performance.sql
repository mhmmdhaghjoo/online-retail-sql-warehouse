-- Which acquisition channels bring customers who come back?
WITH per_customer AS (
    SELECT c.acquisition_channel,
           c.customer_key,
           COUNT(*)           AS orders,
           SUM(o.net_revenue) AS revenue
    FROM marts.orders AS o
    JOIN dw.dim_customer AS c USING (customer_key)
    WHERE c.customer_id IS NOT NULL
    GROUP BY c.acquisition_channel, c.customer_key
)
SELECT acquisition_channel,
       COUNT(*)                                                    AS customers,
       ROUND(AVG(orders), 2)                                       AS avg_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders >= 2) / COUNT(*), 1) AS repeat_rate_pct,
       ROUND(AVG(revenue), 2)                                      AS avg_revenue_per_customer,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue))::numeric, 2) AS median_revenue_per_customer
FROM per_customer
GROUP BY acquisition_channel
ORDER BY avg_revenue_per_customer DESC;
