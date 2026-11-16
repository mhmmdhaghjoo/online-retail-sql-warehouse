-- How many products does it take to make 80 % of each category's revenue?
SELECT category,
       COUNT(*)                                             AS products,
       -- products strictly below 80 %, plus the one that crosses the line
       COUNT(*) FILTER (WHERE cumulative_share_pct - share_of_category_pct < 80) AS products_for_80_pct,
       MAX(product_name) FILTER (WHERE rank_in_category = 1) AS best_seller,
       MAX(share_of_category_pct)                           AS best_seller_share_pct,
       SUM(net_revenue)                                     AS category_revenue
FROM marts.product_performance
GROUP BY category
ORDER BY category_revenue DESC;
