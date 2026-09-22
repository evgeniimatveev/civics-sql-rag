-- ============================================================
-- SQL INTERVIEW PREP — Session 04: Window Functions
-- Dataset: olist -> main_staging.stg_order_payments / stg_orders
--          (same day as session_03_joins.sql, continued while "warmed up")
-- Date: 2026-09-21
-- Progress: ROW_NUMBER + PARTITION BY -> RANK vs DENSE_RANK (ties) ->
--           LAG/LEAD -> running totals -> PARTITION BY + running total
-- Builds on: session_03_joins.sql (JOIN, LEFT JOIN, anti-join)
-- ============================================================


-- ----------------------------------------------------------------
-- LESSON 1: window functions do NOT collapse rows (unlike GROUP BY)
-- ----------------------------------------------------------------
-- Key idea: OVER(...) marks a window function. PARTITION BY works
-- like GROUP BY but without collapsing -- every row stays, you just
-- get an extra calculated column. ORDER BY inside OVER() controls
-- the ranking/ordering WITHIN each partition.

SELECT order_id, payment_sequential, payment_type, payment_value,
  ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC) AS payment_rank
FROM main_staging.stg_order_payments
WHERE order_id = '5262eaeb971616ffef822379ed91896f';
-- Result: voucher $47.55 -> rank 1, credit_card $0.67 -> rank 2
-- (ranked by payment_value DESC, within this one order's partition)

-- Same query across MULTIPLE orders at once -- each order_id gets its
-- own independent numbering, restarting at 1 for every partition:
SELECT order_id, payment_sequential, payment_type, payment_value,
  ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC) AS payment_rank
FROM main_staging.stg_order_payments
WHERE order_id IN (
  SELECT order_id FROM main_staging.stg_order_payments
  GROUP BY order_id HAVING COUNT(*) > 1
)
ORDER BY order_id, payment_rank
LIMIT 10;
-- Result: 3 orders with 2 payments each (ranks 1,2) + 1 order with 4
-- payments (ranks 1,2,3,4) -- partition SIZE depends only on how many
-- rows that specific group has, nothing shared across groups.


-- ----------------------------------------------------------------
-- LESSON 2: ROW_NUMBER vs RANK vs DENSE_RANK — how ties are handled
-- ----------------------------------------------------------------
-- ROW_NUMBER: always unique, even for tied values (arbitrary tiebreak).
-- RANK: ties get the SAME number, then the next rank SKIPS ahead.
-- DENSE_RANK: ties get the same number too, but NEVER skips.

SELECT name, score,
  ROW_NUMBER() OVER (ORDER BY score DESC) AS row_num,
  RANK()       OVER (ORDER BY score DESC) AS rank_val,
  DENSE_RANK() OVER (ORDER BY score DESC) AS dense_rank_val
FROM (VALUES
  ('A', 100),
  ('B', 90),
  ('C', 90),
  ('D', 80)
) AS t(name, score);
-- Result: row_num = 1,2,3,4 (unique even for the B/C tie)
--         rank_val = 1,2,2,4 (B and C share rank 2, D jumps to 4 --
--                             "3" is skipped because 2 spots are used)
--         dense_rank_val = 1,2,2,3 (B and C share rank 2, D gets the
--                             next AVAILABLE rank, no gap)


-- ----------------------------------------------------------------
-- LESSON 3: LAG / LEAD — reading a neighboring row's value
-- ----------------------------------------------------------------
-- LAG looks at the PREVIOUS row's value within the same partition/
-- ordering. LEAD looks at the NEXT row's value. First row has no
-- "previous" (LAG=NULL there); last row has no "next" (LEAD=NULL there).

SELECT order_id, payment_sequential, payment_type, payment_value,
  LAG(payment_value) OVER (PARTITION BY order_id ORDER BY payment_sequential) AS prev_payment_value
FROM main_staging.stg_order_payments
WHERE order_id = '5262eaeb971616ffef822379ed91896f';
-- Result: seq 1 ($0.67) -> prev_payment_value = NULL (no row before it)
--         seq 2 ($47.55) -> prev_payment_value = 0.67

-- Real business use case: month-over-month comparison. Window
-- functions run AFTER GROUP BY, so LAG can apply directly on top of
-- an aggregate like COUNT(*) in the same query -- no subquery needed.
SELECT
  DATE_TRUNC('month', purchased_at) AS order_month,
  COUNT(*) AS order_count,
  LAG(COUNT(*))  OVER (ORDER BY DATE_TRUNC('month', purchased_at)) AS prev_month_count,
  LEAD(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', purchased_at)) AS next_month_count
FROM main_staging.stg_orders
GROUP BY order_month
ORDER BY order_month;
-- Result: 25 months, 2016-09 through 2018-10. First row's
-- prev_month_count = NULL, last row's next_month_count = NULL (mirror
-- of each other, as expected). Peak: Nov 2017 = 7544 orders (matches
-- Brazilian Black Friday timing -- real seasonality, not an anomaly).
-- Tail: Sep/Oct 2018 = 16 and 4 orders -- almost certainly the dataset
-- just ENDS mid-October 2018, not a real business collapse. Interview
-- rule: a sharp drop at the very EDGE of a time series -- check
-- whether the dataset itself is truncated before drawing a business
-- conclusion.


-- ----------------------------------------------------------------
-- LESSON 4: Running totals — SUM() OVER (ORDER BY ...)
-- ----------------------------------------------------------------
-- For each row, a running total adds up every row from the FIRST one
-- through the CURRENT one. Nothing after the current row counts yet.
-- running_total(row N) = running_total(row N-1) + value(row N).

SELECT period, sales,
  SUM(sales) OVER (ORDER BY period) AS running_total
FROM (VALUES
  (1, 10), (2, 5), (3, 20), (4, 15)
) AS t(period, sales);
-- Result: 10, 15, 35, 50
-- (10 | 10+5=15 | 15+20=35 | 35+15=50 -- each step adds its own value
-- to whatever accumulated before it)

-- Add PARTITION BY and the running total RESETS to a fresh sum at the
-- start of each group -- same accumulation logic, just restarted per
-- category. (Note: without category in ORDER BY, group OUTPUT order
-- isn't guaranteed -- add it if display order matters.)
SELECT category, period, sales,
  SUM(sales) OVER (PARTITION BY category ORDER BY period) AS running_total
FROM (VALUES
  ('A', 1, 10), ('A', 2, 20),
  ('B', 1, 5),  ('B', 2, 15), ('B', 3, 10)
) AS t(category, period, sales);
-- Result: A: 10, 30 (2 periods) | B: 5, 20, 30 (3 periods) --
-- verified with 2 more from-scratch practice sets (X/Y categories),
-- both matched hand-calculated predictions exactly.

-- Applied on real data -- cumulative Olist orders over time:
SELECT
  DATE_TRUNC('month', purchased_at) AS order_month,
  COUNT(*) AS order_count,
  SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', purchased_at)) AS running_total
FROM main_staging.stg_orders
GROUP BY order_month
ORDER BY order_month;
-- Result: running_total on the LAST row (2018-10-01) = 99441 --
-- exactly the total order count from session_03's Lesson 1 baseline.
-- Good sanity check: a running total's final value must always equal
-- the plain, un-windowed COUNT(*)/SUM() of the whole dataset.


-- ----------------------------------------------------------------
-- REAL BUG CAUGHT THIS SESSION, worth remembering
-- ----------------------------------------------------------------
-- Schema-discovery query on stg_orders columns initially returned
-- rows from OTHER tables too (review_answer_timestamp, a duplicate
-- purchased_at). Cause: operator precedence -- AND binds tighter than
-- OR, so
--     WHERE table_name = 'stg_orders' AND col LIKE 'a' OR col LIKE 'b' OR col LIKE 'c'
-- parses as
--     (table_name = 'stg_orders' AND col LIKE 'a') OR col LIKE 'b' OR col LIKE 'c'
-- -- the table filter only applied to the FIRST condition. Fix: always
-- wrap the OR group in parentheses:
--     WHERE table_name = 'stg_orders' AND (col LIKE 'a' OR col LIKE 'b' OR col LIKE 'c')


-- ----------------------------------------------------------------
-- WARM-UP FOR NEXT SESSION (run these first, mechanical recall only)
-- ----------------------------------------------------------------
-- 1) ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC)
--    on order 5262eaeb971616ffef822379ed91896f (Lesson 1, from memory)
-- 2) RANK vs DENSE_RANK on the A/B/C/D tie example (Lesson 2, from memory)


-- ────────────────────────────────────────────────────────────
-- NEXT SESSION: CTEs + subqueries (topic #4) — when to use each,
-- how a CTE makes a multi-step window-function query more readable
-- than nesting subqueries.
-- ────────────────────────────────────────────────────────────
