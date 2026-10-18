-- =====================================================================
-- ShopKart E-commerce : SQL Analysis (MySQL 8.0+)
-- Author : Muskan
-- Run schema.sql and data.sql first.
--
-- Metric definitions used throughout:
--   * Revenue  = net revenue of DELIVERED orders only
--                (cancelled / returned / still-shipped orders excluded)
--                net_revenue = quantity * unit_price * (1 - discount_pct/100)
--   * Profit   = net_revenue - quantity * cost_price
--   * Customer behaviour metrics use orders that were NOT cancelled
-- =====================================================================
USE shopkart_db;

-- ---------------------------------------------------------------------
-- 0. Base view: one row per delivered order line
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sales AS
SELECT  oi.order_item_id,
        o.order_id,
        o.customer_id,
        o.order_date,
        p.product_id,
        p.product_name,
        p.category,
        p.brand,
        oi.quantity,
        oi.discount_pct,
        ROUND(oi.quantity * oi.unit_price, 2)                           AS gross_revenue,
        ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100), 2) AS net_revenue,
        ROUND(oi.quantity * p.cost_price, 2)                            AS cogs,
        ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100)
              - oi.quantity * p.cost_price, 2)                          AS profit
FROM order_items oi
JOIN orders   o ON oi.order_id   = o.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.order_status = 'Delivered';


-- =====================================================================
-- SECTION A : BUSINESS OVERVIEW (KPIs)
-- =====================================================================

-- A1. What are the headline numbers of the business?
SELECT  ROUND(SUM(net_revenue), 0)                                  AS total_revenue,
        ROUND(SUM(profit), 0)                                       AS total_profit,
        ROUND(100 * SUM(profit) / SUM(net_revenue), 1)              AS profit_margin_pct,
        COUNT(DISTINCT order_id)                                    AS delivered_orders,
        COUNT(DISTINCT customer_id)                                 AS active_customers,
        ROUND(SUM(net_revenue) / COUNT(DISTINCT order_id), 0)       AS avg_order_value
FROM v_sales;

-- A2. How are orders split by status? (percent of total using a window function)
SELECT  order_status,
        COUNT(*) AS orders,
        ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- A3. Year-wise revenue, profit and growth.
WITH yearly AS (
    SELECT YEAR(order_date) AS yr,
           ROUND(SUM(net_revenue), 0) AS revenue,
           ROUND(SUM(profit), 0)      AS profit
    FROM v_sales
    GROUP BY YEAR(order_date)
)
SELECT yr, revenue, profit,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY yr)) / LAG(revenue) OVER (ORDER BY yr), 1) AS revenue_growth_pct
FROM yearly;


-- =====================================================================
-- SECTION B : SALES TRENDS & SEASONALITY
-- =====================================================================

-- B1. Monthly revenue, orders and average order value.
SELECT  DATE_FORMAT(order_date, '%Y-%m')                       AS month,
        ROUND(SUM(net_revenue), 0)                             AS revenue,
        COUNT(DISTINCT order_id)                               AS orders,
        ROUND(SUM(net_revenue) / COUNT(DISTINCT order_id), 0)  AS aov
FROM v_sales
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;

-- B2. Month-over-month (MoM) revenue growth.
WITH monthly AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, SUM(net_revenue) AS revenue
    FROM v_sales
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT  month,
        ROUND(revenue, 0) AS revenue,
        ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month))
                  / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- B3. Year-over-year (YoY) growth for every month of 2024 vs 2023.
WITH monthly AS (
    SELECT YEAR(order_date) AS yr, MONTH(order_date) AS mth, SUM(net_revenue) AS revenue
    FROM v_sales
    GROUP BY YEAR(order_date), MONTH(order_date)
)
SELECT  cur.mth                                   AS month_no,
        ROUND(prev.revenue, 0)                    AS rev_2023,
        ROUND(cur.revenue, 0)                     AS rev_2024,
        ROUND(100 * (cur.revenue - prev.revenue) / prev.revenue, 1) AS yoy_growth_pct
FROM monthly cur
JOIN monthly prev ON cur.mth = prev.mth AND cur.yr = 2024 AND prev.yr = 2023
ORDER BY cur.mth;

-- B4. Quarterly revenue.
SELECT  YEAR(order_date) AS yr, QUARTER(order_date) AS qtr,
        ROUND(SUM(net_revenue), 0) AS revenue,
        COUNT(DISTINCT order_id)   AS orders
FROM v_sales
GROUP BY YEAR(order_date), QUARTER(order_date)
ORDER BY yr, qtr;

-- B5. Which day of the week sells the most?
SELECT  DAYNAME(order_date) AS weekday,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(net_revenue), 0) AS revenue,
        ROUND(100 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS pct_of_revenue
FROM v_sales
GROUP BY DAYNAME(order_date), WEEKDAY(order_date)
ORDER BY WEEKDAY(order_date);

-- B6. How important is the festive season (Oct-Nov)? Share of yearly revenue.
SELECT  YEAR(order_date) AS yr,
        ROUND(100 * SUM(CASE WHEN MONTH(order_date) IN (10, 11) THEN net_revenue ELSE 0 END)
                  / SUM(net_revenue), 1) AS festive_share_pct
FROM v_sales
GROUP BY YEAR(order_date);

-- B7. Cumulative (running) revenue over time.
WITH monthly AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, SUM(net_revenue) AS revenue
    FROM v_sales GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT month, ROUND(revenue, 0) AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month), 0) AS cumulative_revenue
FROM monthly;

-- B8. 3-month moving average (smooths out seasonality).
WITH monthly AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, SUM(net_revenue) AS revenue
    FROM v_sales GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT month, ROUND(revenue, 0) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3m
FROM monthly;


-- =====================================================================
-- SECTION C : PRODUCT & CATEGORY PERFORMANCE
-- =====================================================================

-- C1. Category performance: revenue, profit, margin and revenue share.
SELECT  category,
        ROUND(SUM(net_revenue), 0)                                   AS revenue,
        ROUND(SUM(profit), 0)                                        AS profit,
        ROUND(100 * SUM(profit) / SUM(net_revenue), 1)               AS margin_pct,
        ROUND(100 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS revenue_share_pct
FROM v_sales
GROUP BY category
ORDER BY revenue DESC;

-- C2. Top 10 products by revenue.
SELECT  product_name, category, SUM(quantity) AS units_sold,
        ROUND(SUM(net_revenue), 0) AS revenue,
        ROUND(100 * SUM(profit) / SUM(net_revenue), 1) AS margin_pct
FROM v_sales
GROUP BY product_id, product_name, category
ORDER BY revenue DESC
LIMIT 10;

-- C3. Top 3 products inside each category.
SELECT category, product_name, revenue, rnk
FROM (
    SELECT category, product_name, ROUND(SUM(net_revenue), 0) AS revenue,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY SUM(net_revenue) DESC) AS rnk
    FROM v_sales
    GROUP BY category, product_id, product_name
) t
WHERE rnk <= 3
ORDER BY category, rnk;

-- C4. Pareto (80/20) analysis: how many products generate 80% of revenue?
WITH product_rev AS (
    SELECT product_id, product_name, SUM(net_revenue) AS revenue
    FROM v_sales GROUP BY product_id, product_name
),
cumulative AS (
    SELECT product_name, revenue,
           SUM(revenue) OVER (ORDER BY revenue DESC) AS cum_revenue,
           SUM(revenue) OVER ()                       AS total_revenue
    FROM product_rev
)
SELECT  COUNT(*) AS products_making_80pct_revenue,
        (SELECT COUNT(*) FROM products) AS total_products
FROM cumulative
WHERE (cum_revenue - revenue) / total_revenue < 0.80;

-- C5. Brands ranked by profit margin (only brands with decent sales).
SELECT  brand, ROUND(SUM(net_revenue), 0) AS revenue,
        ROUND(100 * SUM(profit) / SUM(net_revenue), 1) AS margin_pct
FROM v_sales
GROUP BY brand
HAVING SUM(net_revenue) > 100000
ORDER BY margin_pct DESC
LIMIT 10;

-- C6. Does heavy discounting pay off? Units sold vs margin by discount bucket.
SELECT  CASE WHEN discount_pct = 0 THEN '0%'
             WHEN discount_pct <= 10 THEN '1-10%'
             WHEN discount_pct <= 20 THEN '11-20%'
             ELSE '21%+' END                                    AS discount_bucket,
        COUNT(*)                                                AS order_lines,
        SUM(quantity)                                           AS units,
        ROUND(AVG(quantity), 2)                                 AS avg_units_per_line,
        ROUND(100 * SUM(profit) / SUM(net_revenue), 1)          AS margin_pct
FROM v_sales
GROUP BY discount_bucket
ORDER BY MIN(discount_pct);

-- C7. Best sellers that earn a thin margin (< 25%): candidates for a price review.
SELECT  product_name, category, SUM(quantity) AS units_sold,
        ROUND(SUM(net_revenue), 0) AS revenue,
        ROUND(100 * SUM(profit) / SUM(net_revenue), 1) AS margin_pct
FROM v_sales
GROUP BY product_id, product_name, category
HAVING margin_pct < 25 AND units_sold > 50
ORDER BY revenue DESC;


-- =====================================================================
-- SECTION D : CUSTOMER ANALYTICS
-- =====================================================================

-- D1. Top 10 customers by lifetime revenue.
SELECT  c.customer_id, c.full_name, c.city,
        COUNT(DISTINCT s.order_id) AS orders,
        ROUND(SUM(s.net_revenue), 0) AS lifetime_value
FROM v_sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name, c.city
ORDER BY lifetime_value DESC
LIMIT 10;

-- D2. What % of customers are repeat buyers?
WITH cust_orders AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM orders
    WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
)
SELECT  COUNT(*) AS customers_with_orders,
        SUM(orders = 1)  AS one_time_buyers,
        SUM(orders > 1)  AS repeat_buyers,
        ROUND(100 * SUM(orders > 1) / COUNT(*), 1) AS repeat_rate_pct
FROM cust_orders;

-- D3. RFM segmentation (Recency, Frequency, Monetary) using NTILE.
WITH rfm_base AS (
    SELECT  customer_id,
            DATEDIFF((SELECT MAX(order_date) FROM orders), MAX(order_date)) AS recency_days,
            COUNT(DISTINCT order_id)                                         AS frequency,
            SUM(net_revenue)                                                 AS monetary
    FROM v_sales
    GROUP BY customer_id
),
rfm_score AS (
    SELECT  *,
            NTILE(4) OVER (ORDER BY recency_days DESC) AS r,   -- 4 = most recent
            NTILE(4) OVER (ORDER BY frequency ASC)     AS f,   -- 4 = most frequent
            NTILE(4) OVER (ORDER BY monetary ASC)      AS m    -- 4 = biggest spender
    FROM rfm_base
),
segmented AS (
    SELECT  *,
            CASE WHEN r >= 3 AND f >= 3 AND m >= 3 THEN 'Champions'
                 WHEN f >= 3 AND m >= 3              THEN 'Loyal'
                 WHEN r >= 3 AND f <= 2              THEN 'New / Promising'
                 WHEN r <= 2 AND (f >= 3 OR m >= 3)  THEN 'At Risk'
                 WHEN r = 1                          THEN 'Lost'
                 ELSE 'Needs Attention' END AS segment
    FROM rfm_score
)
SELECT  segment,
        COUNT(*)                         AS customers,
        ROUND(AVG(recency_days), 0)      AS avg_recency_days,
        ROUND(AVG(frequency), 1)         AS avg_orders,
        ROUND(SUM(monetary), 0)          AS revenue,
        ROUND(100 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS revenue_share_pct
FROM segmented
GROUP BY segment
ORDER BY revenue DESC;

-- D4. New vs returning customers every month.
WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_date
    FROM orders WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
)
SELECT  DATE_FORMAT(o.order_date, '%Y-%m') AS month,
        COUNT(DISTINCT CASE WHEN DATE_FORMAT(o.order_date, '%Y-%m') = DATE_FORMAT(f.first_date, '%Y-%m')
                            THEN o.customer_id END) AS new_customers,
        COUNT(DISTINCT CASE WHEN DATE_FORMAT(o.order_date, '%Y-%m') > DATE_FORMAT(f.first_date, '%Y-%m')
                            THEN o.customer_id END) AS returning_customers
FROM orders o
JOIN first_order f ON o.customer_id = f.customer_id
WHERE o.order_status <> 'Cancelled'
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY month;

-- D5. Cohort retention: of customers who first bought in month X,
--     what % came back 1, 2, 3 ... months later? (2023 cohorts)
WITH first_order AS (
    SELECT customer_id, DATE_FORMAT(MIN(order_date), '%Y-%m-01') AS cohort_month
    FROM orders WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id, f.cohort_month,
           TIMESTAMPDIFF(MONTH, f.cohort_month, DATE_FORMAT(o.order_date, '%Y-%m-01')) AS month_no
    FROM orders o
    JOIN first_order f ON o.customer_id = f.customer_id
    WHERE o.order_status <> 'Cancelled'
)
SELECT  DATE_FORMAT(cohort_month, '%Y-%m') AS cohort,
        COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END) AS cohort_size,
        ROUND(100 * COUNT(DISTINCT CASE WHEN month_no = 1 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END), 1) AS m1_pct,
        ROUND(100 * COUNT(DISTINCT CASE WHEN month_no = 2 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END), 1) AS m2_pct,
        ROUND(100 * COUNT(DISTINCT CASE WHEN month_no = 3 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END), 1) AS m3_pct,
        ROUND(100 * COUNT(DISTINCT CASE WHEN month_no = 6 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END), 1) AS m6_pct
FROM activity
WHERE cohort_month < '2024-01-01'
GROUP BY cohort_month
ORDER BY cohort_month;

-- D6. Average days between two consecutive orders of repeat customers.
WITH gaps AS (
    SELECT customer_id,
           DATEDIFF(order_date, LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date)) AS gap_days
    FROM orders
    WHERE order_status <> 'Cancelled'
)
SELECT ROUND(AVG(gap_days), 1) AS avg_days_between_orders
FROM gaps
WHERE gap_days IS NOT NULL;

-- D7. Churn risk: customers who bought before but nothing in the last 90 days.
WITH last_purchase AS (
    SELECT customer_id, MAX(order_date) AS last_order, COUNT(*) AS orders
    FROM orders WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
)
SELECT  COUNT(*) AS inactive_customers,
        SUM(orders >= 3) AS inactive_but_loyal_3plus_orders
FROM last_purchase
WHERE last_order < DATE_SUB((SELECT MAX(order_date) FROM orders), INTERVAL 90 DAY);

-- D8. Does gender or city change spending? Avg order value by gender.
SELECT  c.gender,
        COUNT(DISTINCT s.customer_id) AS customers,
        ROUND(SUM(s.net_revenue) / COUNT(DISTINCT s.order_id), 0) AS aov
FROM v_sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.gender;


-- =====================================================================
-- SECTION E : GEOGRAPHY
-- =====================================================================

-- E1. Revenue by state with share and rank.
SELECT  c.state,
        ROUND(SUM(s.net_revenue), 0) AS revenue,
        ROUND(100 * SUM(s.net_revenue) / SUM(SUM(s.net_revenue)) OVER (), 1) AS share_pct,
        RANK() OVER (ORDER BY SUM(s.net_revenue) DESC) AS state_rank
FROM v_sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.state
ORDER BY revenue DESC;

-- E2. City-level: revenue, customers and revenue per customer.
SELECT  c.city,
        COUNT(DISTINCT c.customer_id) AS buying_customers,
        ROUND(SUM(s.net_revenue), 0)  AS revenue,
        ROUND(SUM(s.net_revenue) / COUNT(DISTINCT c.customer_id), 0) AS revenue_per_customer
FROM v_sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.city
ORDER BY revenue DESC;

-- E3. Favourite category in each city.
SELECT city, category, revenue
FROM (
    SELECT c.city, s.category, ROUND(SUM(s.net_revenue), 0) AS revenue,
           ROW_NUMBER() OVER (PARTITION BY c.city ORDER BY SUM(s.net_revenue) DESC) AS rn
    FROM v_sales s
    JOIN customers c ON s.customer_id = c.customer_id
    GROUP BY c.city, s.category
) t
WHERE rn = 1
ORDER BY revenue DESC;


-- =====================================================================
-- SECTION F : OPERATIONS (cancellations, returns, delivery, payments)
-- =====================================================================

-- F1. Cancellation rate by payment method (is COD a problem?).
SELECT  payment_method,
        COUNT(*) AS orders,
        SUM(order_status = 'Cancelled') AS cancelled,
        ROUND(100 * SUM(order_status = 'Cancelled') / COUNT(*), 1) AS cancel_rate_pct
FROM orders
GROUP BY payment_method
ORDER BY cancel_rate_pct DESC;

-- F2. Return rate by product category (units shipped = delivered + returned).
SELECT  p.category,
        COUNT(*) AS items_delivered_or_returned,
        SUM(o.order_status = 'Returned') AS returned,
        ROUND(100 * SUM(o.order_status = 'Returned') / COUNT(*), 1) AS return_rate_pct
FROM order_items oi
JOIN orders o   ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.order_status IN ('Delivered', 'Returned')
GROUP BY p.category
ORDER BY return_rate_pct DESC;

-- F3. Delivery performance by city: avg days and % of slow (5+ days) deliveries.
SELECT  c.city,
        ROUND(AVG(o.delivery_days), 1) AS avg_delivery_days,
        ROUND(100 * SUM(o.delivery_days >= 5) / COUNT(*), 1) AS slow_delivery_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.delivery_days IS NOT NULL
GROUP BY c.city
ORDER BY avg_delivery_days DESC;

-- F4. Payment method mix over the years.
SELECT  payment_method,
        ROUND(100 * SUM(YEAR(order_date) = 2023) / (SELECT COUNT(*) FROM orders WHERE YEAR(order_date) = 2023), 1) AS pct_2023,
        ROUND(100 * SUM(YEAR(order_date) = 2024) / (SELECT COUNT(*) FROM orders WHERE YEAR(order_date) = 2024), 1) AS pct_2024
FROM orders
GROUP BY payment_method
ORDER BY pct_2024 DESC;


-- =====================================================================
-- SECTION G : MARKETING EFFECTIVENESS
-- =====================================================================

-- G1. Customers acquired and revenue generated per acquisition channel.
SELECT  c.acquisition_channel,
        COUNT(DISTINCT c.customer_id)          AS customers_acquired,
        ROUND(COALESCE(SUM(s.net_revenue), 0), 0) AS revenue,
        ROUND(COALESCE(SUM(s.net_revenue), 0) / COUNT(DISTINCT c.customer_id), 0) AS revenue_per_customer
FROM customers c
LEFT JOIN v_sales s ON c.customer_id = s.customer_id
GROUP BY c.acquisition_channel
ORDER BY revenue DESC;

-- G2. CAC (cost to acquire a customer) and ROAS (revenue per rupee spent) by channel.
WITH spend AS (
    SELECT channel, SUM(spend_amount) AS total_spend
    FROM marketing_spend GROUP BY channel
),
perf AS (
    SELECT c.acquisition_channel AS channel,
           COUNT(DISTINCT c.customer_id) AS customers,
           COALESCE(SUM(s.net_revenue), 0) AS revenue
    FROM customers c
    LEFT JOIN v_sales s ON c.customer_id = s.customer_id
    GROUP BY c.acquisition_channel
)
SELECT  p.channel,
        ROUND(sp.total_spend, 0)                 AS total_spend,
        p.customers,
        ROUND(sp.total_spend / p.customers, 0)   AS cac,
        ROUND(p.revenue / sp.total_spend, 2)     AS roas
FROM perf p
JOIN spend sp ON p.channel = sp.channel
ORDER BY roas DESC;

-- G3. Monthly marketing spend vs revenue (is spend growing faster than sales?).
WITH m_spend AS (
    SELECT DATE_FORMAT(spend_month, '%Y-%m') AS month, SUM(spend_amount) AS spend
    FROM marketing_spend GROUP BY DATE_FORMAT(spend_month, '%Y-%m')
),
m_rev AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, SUM(net_revenue) AS revenue
    FROM v_sales GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT  s.month, ROUND(s.spend, 0) AS spend, ROUND(r.revenue, 0) AS revenue,
        ROUND(100 * s.spend / r.revenue, 1) AS spend_as_pct_of_revenue
FROM m_spend s
JOIN m_rev r ON s.month = r.month
ORDER BY s.month;


-- =====================================================================
-- SECTION H : CUSTOMER REVIEWS
-- =====================================================================

-- H1. Average rating and review volume by category.
SELECT  p.category, COUNT(*) AS reviews, ROUND(AVG(r.rating), 2) AS avg_rating,
        ROUND(100 * SUM(r.rating <= 2) / COUNT(*), 1) AS negative_review_pct
FROM reviews r
JOIN products p ON r.product_id = p.product_id
GROUP BY p.category
ORDER BY avg_rating DESC;

-- H2. High-selling products with weak ratings (quality alarm).
WITH sales AS (
    SELECT product_id, SUM(quantity) AS units, SUM(net_revenue) AS revenue FROM v_sales GROUP BY product_id
),
rating AS (
    SELECT product_id, AVG(rating) AS avg_rating, COUNT(*) AS reviews FROM reviews GROUP BY product_id
)
SELECT  p.product_name, p.category, s.units, ROUND(s.revenue, 0) AS revenue,
        ROUND(r.avg_rating, 2) AS avg_rating, r.reviews
FROM sales s
JOIN rating r   ON s.product_id = r.product_id
JOIN products p ON s.product_id = p.product_id
WHERE r.avg_rating < 3.8 AND r.reviews >= 10
ORDER BY s.revenue DESC;

-- H3. Does slow delivery hurt ratings?
SELECT  CASE WHEN o.delivery_days <= 2 THEN '1-2 days'
             WHEN o.delivery_days <= 4 THEN '3-4 days'
             ELSE '5+ days' END AS delivery_speed,
        COUNT(*) AS reviews,
        ROUND(AVG(r.rating), 2) AS avg_rating
FROM reviews r
JOIN orders o ON r.order_id = o.order_id
GROUP BY delivery_speed
ORDER BY MIN(o.delivery_days);


-- =====================================================================
-- SECTION I : ADVANCED ANALYSIS
-- =====================================================================

-- I1. Market basket: which two products are most often bought together?
SELECT  p1.product_name AS product_a, p2.product_name AS product_b, COUNT(*) AS times_together
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN orders o      ON a.order_id = o.order_id AND o.order_status <> 'Cancelled'
JOIN products p1   ON a.product_id = p1.product_id
JOIN products p2   ON b.product_id = p2.product_id
GROUP BY p1.product_name, p2.product_name
ORDER BY times_together DESC
LIMIT 10;

-- I1b. Same question, but using LIFT so that popular products do not dominate.
--      lift = P(A and B) / (P(A) * P(B));  lift > 1 means a real affinity,
--      lift ~ 1 means the pair appears together only because both sell a lot.
WITH valid_orders AS (
    SELECT order_id FROM orders WHERE order_status <> 'Cancelled'
),
total AS (SELECT COUNT(*) AS n FROM valid_orders),
prod_orders AS (
    SELECT DISTINCT oi.order_id, oi.product_id
    FROM order_items oi JOIN valid_orders v ON oi.order_id = v.order_id
),
single AS (
    SELECT product_id, COUNT(*) AS c FROM prod_orders GROUP BY product_id
),
pairs AS (
    SELECT a.product_id AS pa, b.product_id AS pb, COUNT(*) AS c
    FROM prod_orders a
    JOIN prod_orders b ON a.order_id = b.order_id AND a.product_id < b.product_id
    GROUP BY a.product_id, b.product_id
    HAVING COUNT(*) >= 5
)
SELECT  p1.product_name AS product_a, p2.product_name AS product_b, pr.c AS times_together,
        ROUND((pr.c / t.n) / ((sa.c / t.n) * (sb.c / t.n)), 2) AS lift
FROM pairs pr
CROSS JOIN total t
JOIN single sa   ON pr.pa = sa.product_id
JOIN single sb   ON pr.pb = sb.product_id
JOIN products p1 ON pr.pa = p1.product_id
JOIN products p2 ON pr.pb = p2.product_id
ORDER BY lift DESC
LIMIT 10;

-- I2. Does the first purchase category decide future spending?
WITH first_cat AS (
    SELECT customer_id, category
    FROM (
        SELECT s.customer_id, s.category,
               ROW_NUMBER() OVER (PARTITION BY s.customer_id ORDER BY s.order_date, s.order_item_id) AS rn
        FROM v_sales s
    ) t
    WHERE rn = 1
),
ltv AS (
    SELECT customer_id, SUM(net_revenue) AS ltv, COUNT(DISTINCT order_id) AS orders
    FROM v_sales GROUP BY customer_id
)
SELECT  f.category AS first_purchase_category,
        COUNT(*) AS customers,
        ROUND(AVG(l.ltv), 0)    AS avg_ltv,
        ROUND(AVG(l.orders), 2) AS avg_orders
FROM first_cat f
JOIN ltv l ON f.customer_id = l.customer_id
GROUP BY f.category
ORDER BY avg_ltv DESC;

-- I3. Spike orders: orders worth more than 2x the customer's own average
--     (only customers with 3+ orders). Useful for spotting festive / gifting behaviour.
WITH order_value AS (
    SELECT customer_id, order_id, order_date, SUM(net_revenue) AS order_value
    FROM v_sales GROUP BY customer_id, order_id, order_date
),
scored AS (
    SELECT *,
           AVG(order_value) OVER (PARTITION BY customer_id) AS customer_avg,
           COUNT(*)         OVER (PARTITION BY customer_id) AS customer_orders
    FROM order_value
)
SELECT customer_id, order_id, order_date,
       ROUND(order_value, 0) AS order_value,
       ROUND(customer_avg, 0) AS customer_avg,
       ROUND(order_value / customer_avg, 1) AS times_avg
FROM scored
WHERE customer_orders >= 3 AND order_value > 2 * customer_avg
ORDER BY times_avg DESC
LIMIT 15;

-- I4. Reusable monthly report as a stored procedure.
DROP PROCEDURE IF EXISTS sp_monthly_report;
DELIMITER //
CREATE PROCEDURE sp_monthly_report(IN p_year INT)
BEGIN
    SELECT  MONTH(order_date)                AS month_no,
            MONTHNAME(order_date)            AS month_name,
            COUNT(DISTINCT order_id)         AS orders,
            ROUND(SUM(net_revenue), 0)       AS revenue,
            ROUND(SUM(profit), 0)            AS profit
    FROM v_sales
    WHERE YEAR(order_date) = p_year
    GROUP BY MONTH(order_date), MONTHNAME(order_date)
    ORDER BY month_no;
END //
DELIMITER ;

CALL sp_monthly_report(2024);
