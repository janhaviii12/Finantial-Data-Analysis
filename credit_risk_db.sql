CREATE DATABASE credit_risk_db;
CREATE SCHEMA credit;
SET search_path TO credit;

CREATE TABLE credit.customer (
    customer_id SERIAL PRIMARY KEY,
    employment_length INTEGER,
    annual_income NUMERIC(12,2),
    credit_score INTEGER,
    home_ownership VARCHAR(20),
    verification_status VARCHAR(20)
);

CREATE TABLE credit.loan (
    loan_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES credit.customer(customer_id),
    loan_amount NUMERIC(12,2),
    interest_rate NUMERIC(5,2),
    loan_term INTEGER,
    issue_date DATE,
    loan_status VARCHAR(20)
);

CREATE TABLE credit.payment (
    payment_id SERIAL PRIMARY KEY,
    loan_id INTEGER REFERENCES credit.loan(loan_id),
    due_date DATE,
    payment_date DATE,
    amount_due NUMERIC(12,2),
    amount_paid NUMERIC(12,2),
    days_late INTEGER,
    payment_status VARCHAR(20)
);

CREATE TABLE credit.ops_action (
    action_id SERIAL PRIMARY KEY,
    loan_id INTEGER REFERENCES credit.loan(loan_id),
    action_date DATE,
    action_type VARCHAR(30),
    handled_by VARCHAR(10),
    outcome VARCHAR(30)
);

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'credit';

INSERT INTO credit.customer
(employment_length, annual_income, credit_score, home_ownership, verification_status)
VALUES
(5, 600000, 720, 'RENT', 'Verified'),
(2, 350000, 650, 'OWN', 'Verified'),
(8, 900000, 780, 'MORTGAGE', 'Verified'),
(1, 280000, 620, 'RENT', 'Not Verified');

INSERT INTO credit.loan
(customer_id, loan_amount, interest_rate, loan_term, issue_date, loan_status)
VALUES
(1, 200000, 12.5, 36, '2023-01-10', 'Active'),
(2, 150000, 15.0, 24, '2023-03-05', 'Active'),
(3, 300000, 10.5, 48, '2022-11-20', 'Active'),
(4, 100000, 18.0, 12, '2023-06-15', 'Delinquent');

INSERT INTO credit.payment
(loan_id, due_date, payment_date, amount_due, amount_paid, days_late, payment_status)
VALUES
(1, '2023-08-10', '2023-08-10', 7000, 7000, 0, 'On Time'),
(1, '2023-09-10', '2023-09-15', 7000, 7000, 5, 'Late'),
(2, '2023-09-05', '2023-09-25', 6000, 6000, 20, 'Late'),
(4, '2023-09-15', NULL, 9000, 0, 30, 'Missed');

INSERT INTO credit.ops_action
(loan_id, action_date, action_type, handled_by, outcome)
VALUES
(1, '2023-09-12', 'SMS Reminder', 'auto', 'Paid'),
(2, '2023-09-20', 'Call', 'manual', 'Promise to Pay'),
(4, '2023-09-25', 'Escalation', 'manual', 'No Response');

SELECT
    c.customer_id,
    l.loan_id,
    p.days_late,
    p.payment_status
FROM credit.customer c
JOIN credit.loan l ON c.customer_id = l.customer_id
LEFT JOIN credit.payment p ON l.loan_id = p.loan_id;

SELECT
    loan_id,
    payment_id,
    days_late,
    CASE
        WHEN days_late = 0 THEN '0 DPD'
        WHEN days_late BETWEEN 1 AND 30 THEN '1–30 DPD'
        WHEN days_late BETWEEN 31 AND 60 THEN '31–60 DPD'
        WHEN days_late BETWEEN 61 AND 90 THEN '61–90 DPD'
        ELSE '90+ DPD'
    END AS dpd_bucket
FROM credit.payment;

SELECT
    loan_id,
    MAX(days_late) AS max_dpd
FROM credit.payment
GROUP BY loan_id;

SELECT
    loan_id,
    MAX(days_late) AS max_dpd,
    CASE
        WHEN MAX(days_late) = 0 THEN 'Current'
        WHEN MAX(days_late) BETWEEN 1 AND 30 THEN 'Early Delinquency'
        WHEN MAX(days_late) BETWEEN 31 AND 60 THEN 'High Risk'
        ELSE 'Severe Risk'
    END AS loan_risk_status
FROM credit.payment
GROUP BY loan_id;

WITH monthly_dpd AS (
    SELECT
        loan_id,
        DATE_TRUNC('month', due_date) AS month,
        MAX(days_late) AS max_dpd
    FROM credit.payment
    GROUP BY loan_id, DATE_TRUNC('month', due_date)
)
SELECT * FROM monthly_dpd;

WITH monthly_dpd AS (
    SELECT
        loan_id,
        DATE_TRUNC('month', due_date) AS month,
        MAX(days_late) AS max_dpd
    FROM credit.payment
    GROUP BY loan_id, DATE_TRUNC('month', due_date)
),
dpd_bucketed AS (
    SELECT
        loan_id,
        month,
        CASE
            WHEN max_dpd = 0 THEN '0 DPD'
            WHEN max_dpd BETWEEN 1 AND 30 THEN '1–30 DPD'
            WHEN max_dpd BETWEEN 31 AND 60 THEN '31–60 DPD'
            ELSE '60+ DPD'
        END AS dpd_bucket
    FROM monthly_dpd
)
SELECT * FROM dpd_bucketed;

#Identify First-Time Delinquency
SELECT
    loan_id,
    MIN(due_date) AS first_delinquency_date
FROM credit.payment
WHERE days_late > 0
GROUP BY loan_id;

#Consecutive Late Payments Flag
WITH ordered_payments AS (
    SELECT
        loan_id,
        due_date,
        days_late,
        LAG(days_late) OVER (PARTITION BY loan_id ORDER BY due_date) AS prev_days_late
    FROM credit.payment
)
SELECT
    loan_id,
    due_date,
    days_late,
    CASE
        WHEN days_late > 0 AND prev_days_late > 0 THEN 'EWS: Repeat Late'
        ELSE 'Normal'
    END AS early_warning_flag
FROM ordered_payments;

#Did Ops Action Lead to Payment?
SELECT
    o.loan_id,
    o.action_type,
    o.handled_by,
    o.outcome,
    p.payment_status
FROM credit.ops_action o
LEFT JOIN credit.payment p
ON o.loan_id = p.loan_id
AND p.payment_date >= o.action_date;

#Portfolio Risk Summary
SELECT
    loan_risk_status,
    COUNT(*) AS loan_count
FROM (
    SELECT
        loan_id,
        CASE
            WHEN MAX(days_late) = 0 THEN 'Current'
            WHEN MAX(days_late) BETWEEN 1 AND 30 THEN 'Early Delinquency'
            WHEN MAX(days_late) BETWEEN 31 AND 60 THEN 'High Risk'
            ELSE 'Severe Risk'
        END AS loan_risk_status
    FROM credit.payment
    GROUP BY loan_id
) t
GROUP BY loan_risk_status;

#Loan-Level Risk Summary
CREATE OR REPLACE VIEW credit.vw_loan_risk_summary AS
SELECT
    l.loan_id,
    l.customer_id,
    l.loan_amount,
    l.interest_rate,
    l.loan_term,
    l.issue_date,
    l.loan_status,
    COALESCE(MAX(p.days_late), 0) AS max_dpd,
    CASE
        WHEN COALESCE(MAX(p.days_late), 0) = 0 THEN 'Current'
        WHEN MAX(p.days_late) BETWEEN 1 AND 30 THEN '1–30 DPD'
        WHEN MAX(p.days_late) BETWEEN 31 AND 60 THEN '31–60 DPD'
        ELSE '60+ DPD'
    END AS risk_bucket
FROM credit.loan l
LEFT JOIN credit.payment p
ON l.loan_id = p.loan_id
GROUP BY
    l.loan_id,
    l.customer_id,
    l.loan_amount,
    l.interest_rate,
    l.loan_term,
    l.issue_date,
    l.loan_status;

#Monthly Roll Rate Snapshot
CREATE OR REPLACE VIEW credit.vw_monthly_roll_rate AS
WITH monthly_dpd AS (
    SELECT
        loan_id,
        DATE_TRUNC('month', due_date) AS month,
        MAX(days_late) AS max_dpd
    FROM credit.payment
    GROUP BY loan_id, DATE_TRUNC('month', due_date)
)
SELECT
    loan_id,
    month,
    CASE
        WHEN max_dpd = 0 THEN '0 DPD'
        WHEN max_dpd BETWEEN 1 AND 30 THEN '1–30 DPD'
        WHEN max_dpd BETWEEN 31 AND 60 THEN '31–60 DPD'
        ELSE '60+ DPD'
    END AS dpd_bucket
FROM monthly_dpd;

#Early Warning Signals (EWS)
CREATE OR REPLACE VIEW credit.vw_early_warning_flags AS
WITH ordered_payments AS (
    SELECT
        loan_id,
        due_date,
        days_late,
        LAG(days_late) OVER (PARTITION BY loan_id ORDER BY due_date) AS prev_days_late
    FROM credit.payment
)
SELECT
    loan_id,
    due_date,
    days_late,
    CASE
        WHEN days_late > 0 AND prev_days_late > 0 THEN 1
        ELSE 0
    END AS repeat_late_flag
FROM ordered_payments;

#Ops Effectiveness View
CREATE OR REPLACE VIEW credit.vw_ops_effectiveness AS
SELECT
    o.loan_id,
    o.action_type,
    o.handled_by,
    o.action_date,
    o.outcome,
    COUNT(p.payment_id) AS payments_after_action,
    SUM(p.amount_paid) AS total_amount_collected
FROM credit.ops_action o
LEFT JOIN credit.payment p
ON o.loan_id = p.loan_id
AND p.payment_date >= o.action_date
GROUP BY
    o.loan_id,
    o.action_type,
    o.handled_by,
    o.action_date,
    o.outcome;


#Customer Risk Profile
CREATE OR REPLACE VIEW credit.vw_customer_risk_profile AS
SELECT
    c.customer_id,
    c.employment_length,
    c.annual_income,
    c.credit_score,
    c.home_ownership,
    c.verification_status,
    MAX(p.days_late) AS max_dpd,
    COUNT(DISTINCT l.loan_id) AS total_loans
FROM credit.customer c
LEFT JOIN credit.loan l ON c.customer_id = l.customer_id
LEFT JOIN credit.payment p ON l.loan_id = p.loan_id
GROUP BY
    c.customer_id,
    c.employment_length,
    c.annual_income,
    c.credit_score,
    c.home_ownership,
    c.verification_status;

#verify views
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'credit';
