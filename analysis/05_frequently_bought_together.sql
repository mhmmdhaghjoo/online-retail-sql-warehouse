-- Product pairs that share an order, with lift
-- (how much more often than if the two were bought independently).
WITH baskets AS (
    SELECT DISTINCT order_id, product_key FROM dw.fact_sales
),
totals AS (
    SELECT COUNT(DISTINCT order_id)::numeric AS n_orders FROM baskets
),
product_orders AS (
    SELECT product_key, COUNT(*) AS n FROM baskets GROUP BY product_key
),
pairs AS (
    SELECT a.product_key AS product_a, b.product_key AS product_b, COUNT(*) AS orders_together
    FROM baskets AS a
    JOIN baskets AS b ON a.order_id = b.order_id AND a.product_key < b.product_key
    GROUP BY a.product_key, b.product_key
    HAVING COUNT(*) >= 10
)
SELECT pa.product_name AS product_a,
       pb.product_name AS product_b,
       p.orders_together,
       ROUND(p.orders_together * t.n_orders / (oa.n * ob.n), 2) AS lift
FROM pairs AS p
CROSS JOIN totals AS t
JOIN product_orders AS oa ON oa.product_key = p.product_a
JOIN product_orders AS ob ON ob.product_key = p.product_b
JOIN dw.dim_product AS pa ON pa.product_key = p.product_a
JOIN dw.dim_product AS pb ON pb.product_key = p.product_b
ORDER BY lift DESC, p.orders_together DESC
LIMIT 10;
