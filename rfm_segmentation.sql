-- ============================================================
-- assign 1-5 scores per dimension
-- Business question: How does each customer rank on Recency,
-- Frequency, and Monetary value relative to the rest of the base?
-- ============================================================
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
-- RFM Segmentation — combine scores into business segments
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