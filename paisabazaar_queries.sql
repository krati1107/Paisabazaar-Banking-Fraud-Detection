-- ==========================================================
-- PAISABAZAAR CREDIT RISK ANALYSIS — SQL PART
-- Database used to build/test this: SQLite (paisabazaar.db)
-- Syntax used below is standard SQL — works in MySQL/PostgreSQL
-- with only minor changes (noted where relevant).
-- ==========================================================

-- ---------- SCHEMA ----------
-- Main fact table: one row = one customer-month record
CREATE TABLE customers (
    ID                        INTEGER PRIMARY KEY,
    Customer_ID               INTEGER,
    Month                     INTEGER,
    Name                      TEXT,
    Age                       REAL,
    Occupation                TEXT,
    Annual_Income             REAL,
    Monthly_Inhand_Salary     REAL,
    Num_Bank_Accounts         REAL,
    Num_Credit_Card           REAL,
    Interest_Rate             REAL,
    Num_of_Loan               REAL,
    Delay_from_due_date       REAL,
    Num_of_Delayed_Payment    REAL,
    Num_Credit_Inquiries      REAL,
    Credit_Mix                TEXT,
    Outstanding_Debt          REAL,
    Credit_Utilization_Ratio  REAL,
    Payment_of_Min_Amount     TEXT,
    Total_EMI_per_month       REAL,
    Amount_invested_monthly   REAL,
    Payment_Behaviour         TEXT,
    Monthly_Balance           REAL,
    Credit_Score              TEXT,
    Debt_to_Income_Ratio      REAL,
    Income_per_Account        REAL,
    Income_Group              TEXT
);

-- Small lookup table (used to demonstrate JOINs)
CREATE TABLE occupation_sector (
    Occupation TEXT PRIMARY KEY,
    Sector     TEXT
);

-- ==========================================================
-- LEVEL 1 — BASICS (SELECT, WHERE, ORDER BY, LIMIT)
-- ==========================================================

-- Q1. Show 10 customers with the highest outstanding debt
SELECT Customer_ID, Name, Outstanding_Debt, Credit_Score
FROM customers
ORDER BY Outstanding_Debt DESC
LIMIT 10;

-- Q2. List all customers with a "Poor" credit score and income below 200000
SELECT Customer_ID, Name, Annual_Income, Credit_Score
FROM customers
WHERE Credit_Score = 'Poor' AND Annual_Income < 200000
LIMIT 20;

-- ==========================================================
-- LEVEL 2 — AGGREGATION (GROUP BY, COUNT, AVG, HAVING)
-- ==========================================================

-- Q3. Count of customers per credit score category
SELECT Credit_Score, COUNT(*) AS customer_count
FROM customers
GROUP BY Credit_Score
ORDER BY customer_count DESC;

-- Q4. Average annual income and average debt, by credit score
SELECT Credit_Score,
       ROUND(AVG(Annual_Income), 2)     AS avg_income,
       ROUND(AVG(Outstanding_Debt), 2)  AS avg_debt,
       ROUND(AVG(Debt_to_Income_Ratio), 3) AS avg_dti_ratio
FROM customers
GROUP BY Credit_Score;

-- Q5. Occupations where average delayed payments is above 15
-- (HAVING filters on the aggregated value, WHERE cannot do this)
SELECT Occupation, ROUND(AVG(Num_of_Delayed_Payment), 1) AS avg_delay
FROM customers
GROUP BY Occupation
HAVING AVG(Num_of_Delayed_Payment) > 15
ORDER BY avg_delay DESC;

-- Q6. % of customers who pay only the minimum amount due, per income group
SELECT Income_Group,
       ROUND(100.0 * SUM(CASE WHEN Payment_of_Min_Amount = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_min_payers
FROM customers
GROUP BY Income_Group;

-- ==========================================================
-- LEVEL 3 — JOINS
-- ==========================================================

-- Q7. Average outstanding debt by broader industry Sector
-- (joins the fact table to the small lookup table)
SELECT o.Sector,
       ROUND(AVG(c.Outstanding_Debt), 2) AS avg_debt,
       COUNT(*) AS num_records
FROM customers c
JOIN occupation_sector o ON c.Occupation = o.Occupation
GROUP BY o.Sector
ORDER BY avg_debt DESC;

-- ==========================================================
-- LEVEL 4 — SUBQUERIES
-- ==========================================================

-- Q8. Customers whose outstanding debt is above the overall average debt
SELECT Customer_ID, Name, Outstanding_Debt
FROM customers
WHERE Outstanding_Debt > (SELECT AVG(Outstanding_Debt) FROM customers)
ORDER BY Outstanding_Debt DESC
LIMIT 15;

-- Q9. Occupation(s) with the single highest average annual income
SELECT Occupation, avg_income FROM (
    SELECT Occupation, ROUND(AVG(Annual_Income), 2) AS avg_income
    FROM customers
    GROUP BY Occupation
) t
ORDER BY avg_income DESC
LIMIT 1;

-- ==========================================================
-- LEVEL 5 — WINDOW FUNCTIONS (common interview topic)
-- ==========================================================

-- Q10. Rank customers by Outstanding_Debt within each Credit_Score group
SELECT Customer_ID, Credit_Score, Outstanding_Debt,
       RANK() OVER (PARTITION BY Credit_Score ORDER BY Outstanding_Debt DESC) AS debt_rank
FROM customers
QUALIFY debt_rank <= 3;
-- NOTE: SQLite/older MySQL don't support QUALIFY.
-- Portable version (wrap in a subquery) is Q10b below.

-- Q10b. Same result, portable across all SQL engines
SELECT * FROM (
    SELECT Customer_ID, Credit_Score, Outstanding_Debt,
           RANK() OVER (PARTITION BY Credit_Score ORDER BY Outstanding_Debt DESC) AS debt_rank
    FROM customers
) ranked
WHERE debt_rank <= 3;

-- Q11. Running (cumulative) count of customers per credit score, ordered by income
SELECT Credit_Score, Customer_ID, Annual_Income,
       COUNT(*) OVER (PARTITION BY Credit_Score ORDER BY Annual_Income) AS running_count
FROM customers
ORDER BY Credit_Score, Annual_Income
LIMIT 20;

-- ==========================================================
-- LEVEL 6 — CTE (Common Table Expression) + business logic
-- ==========================================================

-- Q12. Flag high-risk customers using a CTE, then summarize
-- Rule: Debt-to-Income Ratio > 0.4  OR  Num_of_Delayed_Payment > 20
WITH risk_flagged AS (
    SELECT Customer_ID, Credit_Score, Debt_to_Income_Ratio, Num_of_Delayed_Payment,
           CASE
               WHEN Debt_to_Income_Ratio > 0.4 OR Num_of_Delayed_Payment > 20 THEN 'High Risk'
               ELSE 'Normal'
           END AS risk_flag
    FROM customers
)
SELECT risk_flag, Credit_Score, COUNT(*) AS num_customers
FROM risk_flagged
GROUP BY risk_flag, Credit_Score
ORDER BY risk_flag, Credit_Score;

-- Q13. Top 5 occupations by number of "High Risk" flagged customers
WITH risk_flagged AS (
    SELECT Customer_ID, Occupation,
           CASE WHEN Debt_to_Income_Ratio > 0.4 OR Num_of_Delayed_Payment > 20
                THEN 1 ELSE 0 END AS is_high_risk
    FROM customers
)
SELECT Occupation, SUM(is_high_risk) AS high_risk_customers
FROM risk_flagged
GROUP BY Occupation
ORDER BY high_risk_customers DESC
LIMIT 5;

-- ==========================================================
-- LEVEL 7 — MONTH-OVER-MONTH TREND (self-join style)
-- ==========================================================

-- Q14. Average monthly balance trend, month by month
SELECT Month, ROUND(AVG(Monthly_Balance), 2) AS avg_balance
FROM customers
GROUP BY Month
ORDER BY Month;

-- Q15. Customers whose Num_of_Delayed_Payment increased from Month 1 to Month 8
-- (classic "compare two rows of the same customer" interview question)
SELECT m1.Customer_ID,
       m1.Num_of_Delayed_Payment AS delay_month1,
       m8.Num_of_Delayed_Payment AS delay_month8,
       (m8.Num_of_Delayed_Payment - m1.Num_of_Delayed_Payment) AS increase
FROM customers m1
JOIN customers m8
     ON m1.Customer_ID = m8.Customer_ID
    AND m1.Month = 1 AND m8.Month = 8
WHERE m8.Num_of_Delayed_Payment > m1.Num_of_Delayed_Payment
ORDER BY increase DESC
LIMIT 10;
