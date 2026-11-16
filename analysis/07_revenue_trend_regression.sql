-- Linear trend of monthly revenue, fitted in SQL with the regression
-- aggregates: slope in EUR per month and share of variance explained.
WITH numbered AS (
    SELECT ROW_NUMBER() OVER (ORDER BY order_month) AS month_no, net_revenue
    FROM marts.monthly_revenue
)
SELECT COUNT(*)                                        AS months,
       ROUND(REGR_SLOPE(net_revenue, month_no)::numeric, 2)     AS slope_eur_per_month,
       ROUND(REGR_INTERCEPT(net_revenue, month_no)::numeric, 2) AS intercept_eur,
       ROUND(REGR_R2(net_revenue, month_no)::numeric, 3)        AS r_squared,
       ROUND(CORR(net_revenue, month_no)::numeric, 3)           AS correlation
FROM numbered;
