-- Size and value of each RFM segment.
SELECT segment,
       COUNT(*)                         AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers,
       ROUND(AVG(recency_days))         AS avg_recency_days,
       ROUND(AVG(frequency), 1)         AS avg_orders,
       ROUND(AVG(monetary), 2)          AS avg_revenue,
       ROUND(100 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue
FROM marts.customer_rfm
GROUP BY segment
ORDER BY SUM(monetary) DESC;
