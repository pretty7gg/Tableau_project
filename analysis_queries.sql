-- ============================================================
-- MySQL versions — Section 1: JOINS, GROUP BY, HAVING, CASE WHEN
-- ============================================================
USE financial_analytics;

-- Q1. Total spend and transaction count per customer.
-- Business question: Who are our top customers by total spend?
-- SQL concept(s): INNER JOIN, GROUP BY, ORDER BY
SELECT c.customer_id, c.first_name, c.last_name,
       COUNT(t.transaction_id) AS txn_count,
       SUM(t.transaction_amount) AS total_spend
FROM customers c
JOIN transactions t ON t.customer_id = c.customer_id
WHERE t.transaction_status = 'Approved'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spend DESC
LIMIT 20;

-- Q2. Customers who have never transacted.
-- Business question: Which customers signed up but never used a card?
-- SQL concept(s): LEFT JOIN + IS NULL anti-join pattern
SELECT c.customer_id, c.first_name, c.last_name, c.signup_date
FROM customers c
LEFT JOIN transactions t ON t.customer_id = c.customer_id
WHERE t.transaction_id IS NULL;

-- Q3. Merchant category performance: revenue and average ticket size.
-- Business question: Which spending categories drive the most revenue?
-- SQL concept(s): multi-table JOIN, GROUP BY, aggregate functions
SELECT mc.category_name, mc.category_group,
       COUNT(t.transaction_id) AS txn_count,
       SUM(t.transaction_amount) AS revenue,
       ROUND(AVG(t.transaction_amount), 2) AS avg_ticket
FROM transactions t
JOIN merchants m ON m.merchant_id = t.merchant_id
JOIN merchant_categories mc ON mc.category_id = m.category_id
WHERE t.transaction_status = 'Approved'
GROUP BY mc.category_name, mc.category_group
ORDER BY revenue DESC;

-- Q4. Categories with more than 1000 transactions AND avg ticket over $100.
-- Business question: Which high-volume categories are also high-value?
-- SQL concept(s): HAVING (filtering on aggregates, not raw rows)
SELECT mc.category_name,
       COUNT(*) AS txn_count,
       ROUND(AVG(t.transaction_amount), 2) AS avg_ticket
FROM transactions t
JOIN merchants m ON m.merchant_id = t.merchant_id
JOIN merchant_categories mc ON mc.category_id = m.category_id
GROUP BY mc.category_name
HAVING COUNT(*) > 1000 AND AVG(t.transaction_amount) > 100
ORDER BY avg_ticket DESC;
-- no output here

-- Q5. Bucket customers into spend tiers using CASE WHEN.
-- Business question: How many customers fall into each spend tier?
-- SQL concept(s): CASE WHEN inside an aggregate subquery
SELECT spend_tier, COUNT(*) AS customers
FROM (
    SELECT c.customer_id,
           CASE
               WHEN SUM(t.transaction_amount) >= 10000 THEN 'Platinum'
               WHEN SUM(t.transaction_amount) >= 5000  THEN 'Gold'
               WHEN SUM(t.transaction_amount) >= 1000  THEN 'Silver'
               ELSE 'Bronze'
           END AS spend_tier
    FROM customers c
    JOIN transactions t ON t.customer_id = c.customer_id
    WHERE t.transaction_status = 'Approved'
    GROUP BY c.customer_id
) tier_summary
GROUP BY spend_tier
ORDER BY customers DESC;

-- Q6. Transaction success rate by transaction type (POS/Online/ATM).
-- Business question: Is our approval rate weaker for a particular channel?
-- SQL concept(s): CASE WHEN for conditional aggregation
SELECT transaction_type,
       COUNT(*) AS total_txns,
       SUM(CASE WHEN transaction_status = 'Approved' THEN 1 ELSE 0 END) AS approved,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS approval_rate_pct
FROM transactions
GROUP BY transaction_type
ORDER BY approval_rate_pct;

-- Q7. Regional revenue performance via branch -> customer -> transaction chain.
-- Business question: Which regions generate the most revenue?
-- SQL concept(s): 3-way JOIN chain, GROUP BY
SELECT b.region,
       COUNT(DISTINCT c.customer_id) AS customers,
       COUNT(t.transaction_id) AS txns,
       SUM(t.transaction_amount) AS revenue
FROM branches b
JOIN customers c ON c.branch_id = b.branch_id
JOIN transactions t ON t.customer_id = c.customer_id
WHERE t.transaction_status = 'Approved'
GROUP BY b.region
ORDER BY revenue DESC;

-- Q8. Card network mix by income bracket.
-- Business question: Do premium customers prefer certain card networks?
-- SQL concept(s): JOIN + GROUP BY on two dimensions
SELECT c.income_bracket, cd.card_network, COUNT(*) AS card_count
FROM customers c
JOIN cards cd ON cd.customer_id = c.customer_id
GROUP BY c.income_bracket, cd.card_network
ORDER BY c.income_bracket, card_count DESC;

-- ============================================================
-- MySQL versions — Section 2: CTEs
-- ============================================================


-- Q9. Monthly revenue trend using a CTE for readability.
-- Business question: How is total revenue trending month over month?
-- SQL concept(s): CTE, DATE_FORMAT (MySQL's equivalent of DATE_TRUNC)

WITH monthly_revenue AS (
    SELECT DATE_FORMAT(transaction_date, '%Y-%m-01') AS month,
           SUM(transaction_amount) AS revenue,
           COUNT(*) AS txn_count
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY DATE_FORMAT(transaction_date, '%Y-%m-01')
)
SELECT month, revenue, txn_count
FROM monthly_revenue
ORDER BY month;

-- Q10. Top 5 merchants per category by revenue, using a CTE + window function.
-- Business question: Who are the leading merchants inside each category?
-- SQL concept(s): CTE, RANK() OVER (PARTITION BY ...)
WITH merchant_revenue AS (
    SELECT m.merchant_id, m.merchant_name, mc.category_name,
           SUM(t.transaction_amount) AS revenue
    FROM transactions t
    JOIN merchants m ON m.merchant_id = t.merchant_id
    JOIN merchant_categories mc ON mc.category_id = m.category_id
    WHERE t.transaction_status = 'Approved'
    GROUP BY m.merchant_id, m.merchant_name, mc.category_name
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS rnk
    FROM merchant_revenue
)
SELECT category_name, merchant_name, revenue, rnk
FROM ranked
WHERE rnk <= 5
ORDER BY category_name, rnk;

-- Q11. Customer-level RFM raw metrics (feeds the Python segmentation step).
-- Business question: What are each customer's Recency, Frequency, Monetary values?
-- SQL concept(s): CTE, date arithmetic, multiple aggregates
WITH rfm_base AS (
    SELECT customer_id,
           MAX(transaction_date) AS last_txn_date,
           COUNT(*) AS frequency,
           SUM(transaction_amount) AS monetary
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY customer_id
)
SELECT customer_id,
       last_txn_date,
       DATEDIFF(CURRENT_DATE, last_txn_date) AS recency_days,
       frequency,
       monetary
FROM rfm_base
ORDER BY monetary DESC;

-- Q12. New vs. returning customers per month (cohort-style CTE).
-- Business question: How many first-time vs. repeat customers transact each month?
-- SQL concept(s): CTE, date truncation, self-comparison
WITH first_txn AS (
    SELECT customer_id, MIN(DATE_FORMAT(transaction_date, '%Y-%m-01')) AS first_month
    FROM transactions
    GROUP BY customer_id
),
monthly_activity AS (
    SELECT DISTINCT customer_id, DATE_FORMAT(transaction_date, '%Y-%m-01') AS active_month
    FROM transactions
)
SELECT ma.active_month,
       SUM(CASE WHEN ma.active_month = f.first_month THEN 1 ELSE 0 END) AS new_customers,
       SUM(CASE WHEN ma.active_month > f.first_month THEN 1 ELSE 0 END) AS returning_customers
FROM monthly_activity ma
JOIN first_txn f ON f.customer_id = ma.customer_id
GROUP BY ma.active_month
ORDER BY ma.active_month;

-- ============================================================
-- MySQL versions — Section 3: WINDOW FUNCTIONS (LAG/LEAD, ROW_NUMBER, RANK, NTILE)
-- ============================================================
USE financial_analytics;

-- Q13. Month-over-month revenue growth using LAG().
-- Business question: What is the % change in revenue vs. the prior month?
-- SQL concept(s): LAG() window function
WITH monthly AS (
    SELECT DATE_FORMAT(transaction_date, '%Y-%m-01') AS month,
           SUM(transaction_amount) AS revenue
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY DATE_FORMAT(transaction_date, '%Y-%m-01')
)
SELECT month, revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 2) AS pct_growth
FROM monthly
ORDER BY month;

-- Q14. Days between a customer's consecutive transactions, using LEAD().
-- Business question: How frequently does a customer transact (gap analysis for churn)?
-- SQL concept(s): LEAD() window function, PARTITION BY
SELECT customer_id, transaction_date,
       LEAD(transaction_date) OVER (PARTITION BY customer_id ORDER BY transaction_date) AS next_txn_date,
       DATEDIFF(
           LEAD(transaction_date) OVER (PARTITION BY customer_id ORDER BY transaction_date),
           transaction_date
       ) AS days_to_next_txn
FROM transactions
WHERE transaction_status = 'Approved'
ORDER BY customer_id, transaction_date
LIMIT 100;

-- Q15. Rank customers within their income bracket by total spend (top 10 per bracket).
-- Business question: Who are the top spenders inside each income segment?
-- SQL concept(s): RANK() OVER (PARTITION BY ... ORDER BY ...)
-- Note: MySQL doesn't support QUALIFY, so we wrap the windowed query in a subquery instead.
WITH cust_spend AS (
    SELECT c.customer_id, c.income_bracket, SUM(t.transaction_amount) AS total_spend
    FROM customers c
    JOIN transactions t ON t.customer_id = c.customer_id
    WHERE t.transaction_status = 'Approved'
    GROUP BY c.customer_id, c.income_bracket
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY income_bracket ORDER BY total_spend DESC) AS spend_rank
    FROM cust_spend
)
SELECT * FROM ranked WHERE spend_rank <= 10
ORDER BY income_bracket, spend_rank;

-- Q16. Find potential duplicate transactions using ROW_NUMBER().
-- Business question: Same card, same merchant, same amount close together — likely a dupe charge.
-- SQL concept(s): ROW_NUMBER() OVER (PARTITION BY ...) for de-duplication
WITH numbered AS (
    SELECT transaction_id, card_id, merchant_id, transaction_amount, transaction_date,
           ROW_NUMBER() OVER (
               PARTITION BY card_id, merchant_id, transaction_amount
               ORDER BY transaction_date
           ) AS rn
    FROM transactions
)
SELECT * FROM numbered WHERE rn > 1;   -- candidate duplicate charges

-- Q17. Running (cumulative) revenue total per day.
-- Business question: What does our cumulative revenue curve look like over time?
-- SQL concept(s): SUM() OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING)
WITH daily AS (
    SELECT DATE(transaction_date) AS txn_day, SUM(transaction_amount) AS daily_revenue
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY DATE(transaction_date)
)
SELECT txn_day, daily_revenue,
       SUM(daily_revenue) OVER (ORDER BY txn_day ROWS UNBOUNDED PRECEDING) AS running_total
FROM daily
ORDER BY txn_day;

-- Q18. NTILE() to split customers into quartiles by monetary value.
-- Business question: How would a quick quartile-based segmentation look (sanity check vs. RFM)?
-- SQL concept(s): NTILE() window function
WITH cust_spend AS (
    SELECT customer_id, SUM(transaction_amount) AS total_spend
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY customer_id
)
SELECT customer_id, total_spend,
       NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_quartile
FROM cust_spend;

-- ============================================================
-- MySQL versions — Section 4: DATE FUNCTIONS
-- ============================================================


-- Q19. Transactions by day-of-week and hour-of-day (peak activity heatmap source).
-- Business question: When are customers most active — useful for staffing/fraud monitoring windows?
-- SQL concept(s): DAYOFWEEK(), HOUR()
-- Note: MySQL's DAYOFWEEK() returns 1=Sunday, 2=Monday, ... 7=Saturday
SELECT DAYOFWEEK(transaction_date) AS day_of_week,
       HOUR(transaction_date) AS hour_of_day,
       COUNT(*) AS txn_count
FROM transactions
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q20. Customer tenure in months as of today.
-- Business question: How long has each customer been with the bank?
-- SQL concept(s): TIMESTAMPDIFF (MySQL's date-difference function)
SELECT customer_id, signup_date,
       TIMESTAMPDIFF(MONTH, signup_date, CURDATE()) AS tenure_months
FROM customers
ORDER BY tenure_months DESC;

-- Q21. Cards expiring in the next 90 days (proactive renewal outreach list).
-- Business question: Which cards need renewal reminders sent this quarter?
-- SQL concept(s): date range filtering with INTERVAL
SELECT card_id, customer_id, card_type, expiry_date
FROM cards
WHERE expiry_date BETWEEN CURDATE() AND CURDATE() + INTERVAL 90 DAY
  AND is_active = TRUE
ORDER BY expiry_date;

-- Q22. Quarter-over-quarter revenue comparison.
-- Business question: How does revenue compare across fiscal quarters?
-- SQL concept(s): YEAR() + QUARTER()
SELECT CONCAT(YEAR(transaction_date), '-Q', QUARTER(transaction_date)) AS quarter,
       SUM(transaction_amount) AS revenue
FROM transactions
WHERE transaction_status = 'Approved'
GROUP BY 1
ORDER BY 1;


-- ============================================================
-- Section 5: FRAUD & RISK ANALYSIS
-- (MySQL-compatible as-is, no syntax changes needed)
-- ============================================================


-- Q23. Fraud rate by merchant risk level and transaction type.
-- Business question: Where should fraud monitoring focus first?
-- SQL concept(s): JOIN, conditional aggregation
SELECT m.risk_level, t.transaction_type,
       COUNT(*) AS total_txns,
       SUM(CASE WHEN t.is_fraud THEN 1 ELSE 0 END) AS fraud_txns,
       ROUND(100.0 * SUM(CASE WHEN t.is_fraud THEN 1 ELSE 0 END) / COUNT(*), 3) AS fraud_rate_pct
FROM transactions t
JOIN merchants m ON m.merchant_id = t.merchant_id
GROUP BY m.risk_level, t.transaction_type
ORDER BY fraud_rate_pct DESC;

-- Q24. Customers with more than one fraud incident (repeat-victim pattern).
-- Business question: Which customers may need proactive card reissue / extra monitoring?
-- SQL concept(s): JOIN, GROUP BY, HAVING
SELECT t.customer_id, COUNT(*) AS fraud_incidents, SUM(t.transaction_amount) AS fraud_exposure
FROM transactions t
WHERE t.is_fraud = TRUE
GROUP BY t.customer_id
HAVING COUNT(*) > 1
ORDER BY fraud_incidents DESC;

-- Q25. Average fraud score by flag reason (from the fraud_flags detail table).
-- Business question: Which fraud signals tend to be highest-confidence?
-- SQL concept(s): JOIN, GROUP BY, AVG
SELECT ff.flag_reason, COUNT(*) AS flagged_count, ROUND(AVG(ff.fraud_score), 2) AS avg_score
FROM fraud_flags ff
GROUP BY ff.flag_reason
ORDER BY avg_score DESC;


-- ============================================================
-- MySQL versions — Section 6: CUSTOMER VALUE / SEGMENTATION SUPPORT
-- ============================================================


-- Q26. Customer Lifetime Value proxy: total approved spend since signup, annualized.
-- Business question: What is each customer's approximate annualized value?
-- SQL concept(s): CTE, date math, division guard with NULLIF/GREATEST
WITH cust_spend AS (
    SELECT c.customer_id, c.signup_date, SUM(t.transaction_amount) AS total_spend
    FROM customers c
    JOIN transactions t ON t.customer_id = c.customer_id
    WHERE t.transaction_status = 'Approved'
    GROUP BY c.customer_id, c.signup_date
)
SELECT customer_id, total_spend,
       GREATEST(TIMESTAMPDIFF(MONTH, signup_date, CURDATE()) / 12.0, 0.1) AS years_active,
       ROUND(total_spend / GREATEST(TIMESTAMPDIFF(MONTH, signup_date, CURDATE()) / 12.0, 0.1), 2) AS annualized_value
FROM cust_spend
ORDER BY annualized_value DESC
LIMIT 20;

-- Q27. Retention indicator: customers active in the current month AND the prior month.
-- Business question: What is our month-over-month retention rate?
-- SQL concept(s): self-JOIN across two date-filtered CTEs
WITH this_month AS (
    SELECT DISTINCT customer_id FROM transactions
    WHERE transaction_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
),
last_month AS (
    SELECT DISTINCT customer_id FROM transactions
    WHERE transaction_date >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01')
      AND transaction_date <  DATE_FORMAT(CURDATE(), '%Y-%m-01')
)
SELECT
    (SELECT COUNT(*) FROM last_month) AS active_last_month,
    (SELECT COUNT(*) FROM this_month tm JOIN last_month lm ON tm.customer_id = lm.customer_id) AS retained,
    ROUND(100.0 *
        (SELECT COUNT(*) FROM this_month tm JOIN last_month lm ON tm.customer_id = lm.customer_id)
        / NULLIF((SELECT COUNT(*) FROM last_month), 0), 2) AS retention_rate_pct;

-- Q28. Cross-sell opportunity: customers with only one active card type.
-- Business question: Who is a candidate for a second product (e.g., add a credit card)?
-- SQL concept(s): GROUP BY + HAVING on distinct counts
SELECT customer_id, COUNT(DISTINCT card_type) AS distinct_card_types
FROM cards
WHERE is_active = TRUE
GROUP BY customer_id
HAVING COUNT(DISTINCT card_type) = 1;

-- ============================================================
-- MySQL versions — Section 7: VIEWS & STORED PROCEDURES
-- ============================================================


-- Q29. A reusable VIEW for executive KPI reporting (feeds Tableau directly).
-- Business question: Give BI tools a single stable source for headline KPIs.
-- SQL concept(s): CREATE VIEW
-- Note: MySQL doesn't support FILTER (WHERE ...) like Postgres — use
-- SUM(CASE WHEN ... THEN amount ELSE 0 END) instead.
CREATE OR REPLACE VIEW vw_monthly_kpis AS
SELECT DATE_FORMAT(t.transaction_date, '%Y-%m-01') AS month,
       COUNT(DISTINCT t.customer_id) AS active_customers,
       COUNT(t.transaction_id) AS txn_count,
       SUM(CASE WHEN t.transaction_status = 'Approved' THEN t.transaction_amount ELSE 0 END) AS revenue,
       ROUND(100.0 * SUM(CASE WHEN t.is_fraud THEN 1 ELSE 0 END) / COUNT(*), 3) AS fraud_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN t.transaction_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS approval_rate_pct
FROM transactions t
GROUP BY 1;

-- Usage:
SELECT * FROM vw_monthly_kpis ORDER BY month;


-- ============================================================
-- Q30. Stored procedure: parameterized customer spend summary.
-- Business question: Give analysts a callable procedure instead of rewriting the query each time.
-- SQL concept(s): CREATE PROCEDURE
--
-- Note: MySQL requires changing the DELIMITER before creating a procedure,
-- because the procedure body itself contains semicolons that would otherwise
-- end the CREATE PROCEDURE statement early. Run this whole block together
-- (select all of it and execute at once, not line-by-line).
-- ============================================================

DELIMITER //

CREATE PROCEDURE get_customer_summary(IN p_customer_id INT)
BEGIN
    SELECT t.customer_id,
           COUNT(*) AS txn_count,
           SUM(t.transaction_amount) AS total_spend,
           ROUND(AVG(t.transaction_amount), 2) AS avg_ticket,
           MAX(t.transaction_date) AS last_txn_date
    FROM transactions t
    WHERE t.customer_id = p_customer_id
      AND t.transaction_status = 'Approved'
    GROUP BY t.customer_id;
END //

DELIMITER ;

-- Usage: pick any real customer_id from your data, e.g.:
-- CALL get_customer_summary(105);

-- ============================================================
-- Q11b. RFM Scoring — assign 1-5 scores per dimension
-- Business question: How does each customer rank on Recency,
-- Frequency, and Monetary value relative to the rest of the base?
-- SQL concept(s): CTE, NTILE() for quintile scoring
-- Note: Recency is inverted — a LOWER recency_days (more recent)
-- should get a HIGHER score, so we order ASC for recency's NTILE.
-- ============================================================
WITH rfm_base AS (
    SELECT customer_id,
           DATEDIFF(CURRENT_DATE, MAX(transaction_date)) AS recency_days,
           COUNT(*) AS frequency,
           SUM(transaction_amount) AS monetary
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY customer_id
)
SELECT customer_id,
       recency_days,
       frequency,
       monetary,
       NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,   -- lower days = more recent = higher score
       NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,   -- higher freq = higher score
       NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score    -- higher spend = higher score
FROM rfm_base
ORDER BY customer_id;


-- ============================================================
-- Q11c. RFM Segmentation — combine scores into business segments
-- Business question: Which actionable customer segment does each
-- customer fall into (Champions, Loyal, At Risk, Lost, etc.)?
-- SQL concept(s): CTE stacking, string concatenation, CASE WHEN
-- ============================================================
WITH rfm_base AS (
    SELECT customer_id,
           DATEDIFF(CURRENT_DATE, MAX(transaction_date)) AS recency_days,
           COUNT(*) AS frequency,
           SUM(transaction_amount) AS monetary
    FROM transactions
    WHERE transaction_status = 'Approved'
    GROUP BY customer_id
),
rfm_scored AS (
    SELECT customer_id, recency_days, frequency, monetary,
           NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
           NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
           NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM rfm_base
)
SELECT customer_id,
       recency_days, frequency, monetary,
       r_score, f_score, m_score,
       CONCAT(r_score, f_score, m_score) AS rfm_cell,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
           WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
           WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'At Risk'
           WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost'
           WHEN r_score <= 2                                   THEN 'Hibernating'
           ELSE 'Needs Attention'
       END AS customer_segment
FROM rfm_scored
ORDER BY rfm_cell DESC;