-- ============================================================
-- SQL INTERVIEW PREP — Session 03: JOINs (INNER, LEFT, anti-join)
-- Dataset: olist -> main_staging.stg_orders / stg_order_payments /
--          stg_order_reviews (real Brazilian e-commerce marketplace data)
-- Date: 2026-09-21 (topic opened 2026-09-05/08/19, completed hands-on today)
-- Progress: row-multiplication trap -> COUNT(*) vs COUNT(DISTINCT) gotcha
--           -> LEFT JOIN -> anti-join -> a real business hypothesis test
-- Builds on: session_02_group_by.sql (GROUP BY, HAVING, aliases)
-- Switched datasets from uber_analytics to olist here because
-- uber_analytics.trips has no real foreign key into payments/ratings
-- (trip_id is a bare SERIAL int, payments.trip_uuid doesn't map to it) —
-- olist has real FKs: orders.order_id <-> payments.order_id <-> reviews.order_id
-- ============================================================


-- ----------------------------------------------------------------
-- LESSON 1: JOIN duplicates rows — it is a MATCH-FINDER, not a merge
-- ----------------------------------------------------------------
-- Key idea: for every row on the left, JOIN looks for ALL matching
-- rows on the right (per the ON condition) and emits one output row
-- PER MATCH. If a key on the right has 2 matches, the left row gets
-- duplicated twice. JOIN is not "look up and attach once."

SELECT COUNT(*) FROM main_staging.stg_orders;
-- Result: 99441 (one row per order — the baseline)

SELECT COUNT(*)
FROM main_staging.stg_orders o
JOIN main_staging.stg_order_payments p
  ON o.order_id = p.order_id;
-- Result: 103886 -- MORE than 99441. Some orders have more than one
-- payment row (split payments), and each extra payment row duplicates
-- that order's row in the JOIN output.

-- See it on one real order (found via GROUP BY ... HAVING COUNT(*) > 1):
SELECT order_id, COUNT(*) AS payment_rows
FROM main_staging.stg_order_payments
GROUP BY order_id
HAVING COUNT(*) > 1
LIMIT 5;
-- Result includes: 5262eaeb971616ffef822379ed91896f -> 2 payment rows

SELECT o.order_id, o.order_status, p.payment_sequential, p.payment_type, p.payment_value
FROM main_staging.stg_orders o
JOIN main_staging.stg_order_payments p
  ON o.order_id = p.order_id
WHERE o.order_id = '5262eaeb971616ffef822379ed91896f';
-- Result: 2 rows. order_id/order_status ("delivered") are IDENTICAL in
-- both rows (that's the duplication) -- but payment_sequential/
-- payment_type/payment_value differ: (1, credit_card, $0.67) and
-- (2, voucher, $47.55). One order, split across two payment methods,
-- so the order row appears twice after the JOIN.


-- ----------------------------------------------------------------
-- LESSON 2: the COUNT(*) gotcha — rows after JOIN != entities you think
-- ----------------------------------------------------------------
-- Filtering with WHERE reduces which ORDERS qualify, but the JOIN
-- still multiplies rows within that filtered subset. Result: COUNT(*)
-- after a JOIN can be even LARGER than the count of ALL orders before
-- any filter at all -- an easy trap in a real report.

SELECT COUNT(*)
FROM main_staging.stg_orders o
JOIN main_staging.stg_order_payments p
  ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';
-- Result: 100756

SELECT COUNT(*)
FROM main_staging.stg_orders
WHERE order_status = 'delivered';
-- Result: 96478 -- the REAL number of delivered orders.

-- 100756 > 96478 AND > 99441 (total orders, every status combined).
-- Filtering to "delivered" shrank the order count, but the JOIN to
-- payments still inflated the row count past even the unfiltered
-- total. Rule: COUNT(*) after a JOIN answers "how many matched rows,"
-- never "how many orders" -- for that, use COUNT(DISTINCT order_id).


-- ----------------------------------------------------------------
-- LESSON 3: LEFT JOIN + anti-join — finding "no match" rows
-- ----------------------------------------------------------------
-- LEFT JOIN keeps EVERY row from the left table, even with no match
-- on the right -- unmatched rows just get NULL in the right-side
-- columns instead of disappearing (which is what INNER JOIN would do).

-- Table name found via schema discovery (3 candidates existed --
-- mart_reviews / raw_order_reviews / stg_order_reviews -- picked the
-- stg_ layer for consistency with stg_orders/stg_order_payments):
SELECT table_name FROM information_schema.tables WHERE table_name LIKE '%review%';

SELECT COUNT(*)
FROM main_staging.stg_orders o
LEFT JOIN main_staging.stg_order_reviews r
  ON o.order_id = r.order_id;
-- Result: 99992 -- more than 99441, same row-multiplication cause as
-- Lesson 1 (some orders have 2+ reviews), but NO orders are dropped.

-- Anti-join pattern: LEFT JOIN, then filter WHERE the right-side key
-- IS NULL. Only rows with zero matches on the right survive this --
-- because those are exactly the rows where every right-side column
-- came back NULL.
SELECT COUNT(*)
FROM main_staging.stg_orders o
LEFT JOIN main_staging.stg_order_reviews r
  ON o.order_id = r.order_id
WHERE r.order_id IS NULL;
-- Result: 768 -- orders with ZERO reviews (768 / 99441 = ~0.77%)

-- General rule (self-generalized correctly in-session): this row-
-- multiplication / anti-join mechanic applies to ANY joined table --
-- payments, reviews, order line items, anything -- not a special case
-- of this one dataset.


-- ----------------------------------------------------------------
-- BONUS: hypothesize, then verify with data (real DA instinct)
-- ----------------------------------------------------------------
-- Question raised: why is the no-review rate only ~0.77% when a
-- typical e-commerce site sees most customers skip reviewing?
-- Hypothesis 1 (correct): Olist auto-sends a post-delivery
-- satisfaction survey to every customer -- it's a built-in process
-- step, not an organic/optional review like Amazon's.
-- Hypothesis 2 (correct, and verified below): the survey's core ask
-- is a 1-5 star click (review_score), and the written comment is
-- optional -- so most people just click a star rating.

SELECT
    COUNT(*)                                              AS total_reviews,
    COUNT(comment_message)                                AS with_comment,
    ROUND(100.0 * COUNT(comment_message) / COUNT(*), 1)   AS pct_with_comment
FROM main_staging.stg_order_reviews;
-- Result: 99224 total / 40977 with_comment / 41.3%
-- Confirms the hypothesis: 58.7% of reviews are JUST a star rating,
-- no written text at all. Directionally right, magnitude a bit lower
-- than first guessed -- good interview lesson: verify the SIZE of an
-- effect with data, don't just confirm the DIRECTION and stop there.


-- ----------------------------------------------------------------
-- WARM-UP FOR NEXT SESSION (run these first, mechanical recall only)
-- ----------------------------------------------------------------
-- 1) COUNT(*) on stg_orders vs COUNT(*) after JOIN to stg_order_payments
--    (Lesson 1, from memory -- expect 99441 vs 103886)
-- 2) Anti-join for orders with no review (Lesson 3, from memory --
--    expect 768)


-- ────────────────────────────────────────────────────────────
-- NEXT SESSION: Window functions (topic #3) — ROW_NUMBER, RANK,
-- DENSE_RANK, LAG/LEAD, running totals. Started same day (2026-09-21)
-- on stg_order_payments: ROW_NUMBER() OVER (PARTITION BY order_id
-- ORDER BY payment_value DESC) on the same 5262eaeb... order used in
-- Lesson 1 above, to introduce OVER()/PARTITION BY without switching
-- to unfamiliar data at the same time as unfamiliar syntax.
-- ────────────────────────────────────────────────────────────
