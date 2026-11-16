-- 05_marts.sql
-- Reporting views on top of the star schema. Analysts query these, not the
-- fact table, so every business definition lives in exactly one place.

DROP SCHEMA IF EXISTS marts CASCADE;
CREATE SCHEMA marts;

-- One row per order (the fact table is one row per order line).
CREATE VIEW marts.orders AS
SELECT f.order_id,
       MIN(f.order_ts)    AS order_ts,
       MIN(d.full_date)   AS order_date,
       MIN(d.month_start) AS order_month,
       f.customer_key,
       SUM(f.quantity)    AS items,
       SUM(f.net_revenue) AS net_revenue,
       SUM(f.net_revenue - f.cost) AS gross_margin
FROM dw.fact_sales AS f
JOIN dw.dim_date AS d USING (date_key)
GROUP BY f.order_id, f.customer_key;

-- Monthly KPIs with month-over-month growth, a three-month moving average
-- and a running year-to-date total.
CREATE VIEW marts.monthly_revenue AS
WITH monthly AS (
    SELECT order_month,
           COUNT(*)                     AS orders,
           COUNT(DISTINCT customer_key) AS customers,
           SUM(net_revenue)             AS net_revenue,
           SUM(gross_margin)            AS gross_margin
    FROM marts.orders
    GROUP BY order_month
)
SELECT order_month,
       orders,
       customers,
       net_revenue,
       ROUND(net_revenue / orders, 2) AS avg_order_value,
       ROUND(100 * gross_margin / net_revenue, 1) AS margin_pct,
       ROUND(100 * (net_revenue / LAG(net_revenue) OVER w - 1), 1)  AS mom_growth_pct,
       ROUND(100 * (net_revenue / LAG(net_revenue, 12) OVER w - 1), 1) AS yoy_growth_pct,
       ROUND(AVG(net_revenue) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS revenue_3m_avg,
       SUM(net_revenue) OVER (PARTITION BY DATE_TRUNC('year', order_month) ORDER BY order_month) AS revenue_ytd
FROM monthly
WINDOW w AS (ORDER BY order_month);

-- Cohort retention: customers grouped by the month of their first order,
-- followed over the months after it.
CREATE VIEW marts.cohort_retention AS
WITH known_orders AS (
    SELECT o.customer_key, o.order_month
    FROM marts.orders AS o
    JOIN dw.dim_customer AS c USING (customer_key)
    WHERE c.customer_id IS NOT NULL
),
first_order AS (
    SELECT customer_key, MIN(order_month) AS cohort_month
    FROM known_orders
    GROUP BY customer_key
),
activity AS (
    SELECT DISTINCT
           f.cohort_month,
           k.customer_key,
           (EXTRACT(year FROM AGE(k.order_month, f.cohort_month)) * 12
            + EXTRACT(month FROM AGE(k.order_month, f.cohort_month)))::integer AS months_since_first
    FROM known_orders AS k
    JOIN first_order AS f USING (customer_key)
),
counts AS (
    SELECT cohort_month, months_since_first, COUNT(*) AS active_customers
    FROM activity
    GROUP BY cohort_month, months_since_first
)
SELECT cohort_month,
       months_since_first,
       FIRST_VALUE(active_customers) OVER w AS cohort_size,
       active_customers,
       ROUND(100.0 * active_customers / FIRST_VALUE(active_customers) OVER w, 1) AS retention_pct
FROM counts
WINDOW w AS (PARTITION BY cohort_month ORDER BY months_since_first);

-- RFM: recency, frequency and monetary value scored 1-5 with NTILE, then
-- mapped to named segments a marketing team can act on.
CREATE VIEW marts.customer_rfm AS
WITH reference AS (
    SELECT MAX(order_date) + 1 AS as_of FROM marts.orders
),
base AS (
    SELECT c.customer_key,
           c.customer_id,
           c.country,
           c.acquisition_channel,
           (SELECT as_of FROM reference) - MAX(o.order_date) AS recency_days,
           COUNT(*)           AS frequency,
           SUM(o.net_revenue) AS monetary
    FROM marts.orders AS o
    JOIN dw.dim_customer AS c USING (customer_key)
    WHERE c.customer_id IS NOT NULL
    GROUP BY c.customer_key, c.customer_id, c.country, c.acquisition_channel
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- 5 = most recent
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM base
)
SELECT *,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
           WHEN r_score >= 4 AND frequency = 1 THEN 'New'
           WHEN r_score >= 3 THEN 'Promising'
           WHEN f_score >= 4 THEN 'At risk'
           WHEN r_score = 2 THEN 'Needs attention'
           ELSE 'Lost'
       END AS segment
FROM scored;

-- Product ranking inside each category, with the cumulative revenue share
-- that shows how concentrated the category is.
CREATE VIEW marts.product_performance AS
WITH product_sales AS (
    SELECT p.product_key, p.product_id, p.product_name, p.category,
           SUM(f.quantity)             AS units,
           SUM(f.net_revenue)          AS net_revenue,
           SUM(f.net_revenue - f.cost) AS gross_margin
    FROM dw.fact_sales AS f
    JOIN dw.dim_product AS p USING (product_key)
    GROUP BY p.product_key, p.product_id, p.product_name, p.category
)
SELECT product_id, product_name, category, units, net_revenue,
       ROUND(100 * gross_margin / net_revenue, 1) AS margin_pct,
       RANK() OVER (PARTITION BY category ORDER BY net_revenue DESC) AS rank_in_category,
       ROUND(100 * net_revenue / SUM(net_revenue) OVER (PARTITION BY category), 1) AS share_of_category_pct,
       ROUND(100 * SUM(net_revenue) OVER (PARTITION BY category ORDER BY net_revenue DESC
                                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                 / SUM(net_revenue) OVER (PARTITION BY category), 1) AS cumulative_share_pct
FROM product_sales;
