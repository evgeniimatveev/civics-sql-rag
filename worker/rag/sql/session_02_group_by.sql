-- ============================================================
-- SQL INTERVIEW PREP — Session 02: GROUP BY + Aggregates
-- Dataset: uber_analytics -> trips table (real personal Uber driving data)
-- Date: 2026-09-02
-- Progress: GROUP BY -> aliases (AS) -> ORDER BY on aggregates ->
--           HAVING -> multi-column GROUP BY -> a real timezone bug
-- Builds on: session_01_basics.sql (SELECT/WHERE/ORDER BY/NULL/aggregates)
-- ============================================================


-- ----------------------------------------------------------------
-- LESSON 1: GROUP BY — collapse rows into groups, aggregate PER GROUP
-- ----------------------------------------------------------------
-- Key idea vs Session 01: WHERE filters ROWS before grouping.
-- GROUP BY collapses rows sharing a value into one group, and every
-- aggregate function (COUNT/SUM/AVG...) is then computed INSIDE each
-- group separately, not across the whole table.

SELECT
    status,
    COUNT(*) AS trip_count
FROM trips
GROUP BY status
ORDER BY trip_count DESC;
-- Result: completed=3451, rider_canceled=253, driver_canceled=41


-- ----------------------------------------------------------------
-- LESSON 2: Multiple aggregates + clean aliases in one GROUP BY
-- ----------------------------------------------------------------
-- Every non-aggregated column in SELECT must appear in GROUP BY.
-- Use AS to name derived columns clearly — this is what makes a
-- result set readable to whoever reviews the query later (including you).

SELECT
    status,
    COUNT(*)                            AS trip_count,
    ROUND(AVG(original_fare_usd), 2)    AS avg_fare
FROM trips
GROUP BY status
ORDER BY trip_count DESC;
-- Result: completed 3451 / $20.52 avg | rider_canceled 253 / $1.95 |
--         driver_canceled 41 / $6.04
-- Insight: cancelled trips are NOT $0 or NULL — Uber charges a real
-- cancellation fee, higher when the DRIVER cancels (compensates for
-- the wasted pickup drive) than when the rider does.

-- Reminder from Session 01, confirmed here: aggregate functions
-- silently IGNORE NULLs. completed has 3451 rows but only 3448 have
-- a non-null fare (3 rows are the known NULL-fare data bug) — AVG
-- divided by 3448, not 3451, with no warning. Always know your
-- denominator when a NULL-able column feeds an aggregate.


-- ----------------------------------------------------------------
-- LESSON 3: ORDER BY on an aggregate alias — ASC vs DESC, your choice
-- ----------------------------------------------------------------
-- You can ORDER BY the alias you just created in SELECT.
-- DESC = largest first, ASC = smallest first (ASC is the default
-- if you omit it entirely).

SELECT
    status,
    ROUND(AVG(original_fare_usd), 2) AS avg_fare
FROM trips
GROUP BY status
ORDER BY avg_fare ASC;   -- cheapest average first this time
-- Result: rider_canceled $1.95 -> driver_canceled $6.04 -> completed $20.52


-- ----------------------------------------------------------------
-- LESSON 4: real bug encountered live — timezone trap on timestamptz
-- ----------------------------------------------------------------
-- Task: trips + avg fare BY HOUR OF DAY.
-- trips.begintrip_at is `timestamp with time zone` — Postgres always
-- stores/display these in the SESSION's timezone setting. This
-- session's Postgres is already set to America/Los_Angeles (same as
-- every city in this dataset), so the plain, no-conversion version
-- below is already correct local time:

SELECT
    EXTRACT(HOUR FROM begintrip_at) AS local_hour,
    COUNT(*) AS trip_count,
    ROUND(AVG(original_fare_usd), 2) AS avg_fare
FROM trips
WHERE status = 'completed'
GROUP BY local_hour
ORDER BY local_hour;
-- Result: real peak is 21:00-02:00 (199 / 631 / 812 / 798 / 583 / 292
-- trips), matching actual driving hours (night-shift pattern) —
-- confirmed against real personal knowledge of when these trips
-- happened, not just trusting the query.

-- THE BUG I ACTUALLY MADE mid-session, worth keeping as a warning:
-- I "fixed" the query defensively with a double conversion —
--     EXTRACT(HOUR FROM begintrip_at AT TIME ZONE 'UTC' AT TIME ZONE timezone)
-- — assuming the raw value was in UTC. It wasn't (session tz already
-- matched the data), so this took an already-correct local hour,
-- mislabeled it as UTC, and shifted it AGAIN — silently producing a
-- fake "5-9am peak" that looked plausible but was flatly wrong.
-- Caught only because the real answer (9pm-3am) was checked against
-- lived experience, not just "does the query run without error."
--
-- The GENERAL correct pattern (safe even if this dataset ever mixes
-- multiple cities/timezones, or the session default ever changes) is
-- a SINGLE conversion using each row's own timezone column:
--     EXTRACT(HOUR FROM begintrip_at AT TIME ZONE timezone)
-- One AT TIME ZONE step is "convert this instant into that zone's
-- local wall-clock." A second one on top re-interprets wall-clock as
-- UTC and shifts again — only correct if that's genuinely what you
-- have, which here it was not.
--
-- Lesson for interviews: a wrong query rarely throws an error — it
-- just returns a plausible-looking wrong number. Sanity-check derived
-- results (especially date/time and timezone work) against something
-- you independently know to be true.


-- ----------------------------------------------------------------
-- LESSON 5: HAVING — filter GROUPS, not rows (runs after GROUP BY)
-- ----------------------------------------------------------------
-- WHERE can't reference an aggregate (COUNT/AVG don't exist yet when
-- WHERE runs). HAVING runs after grouping, so it can.

SELECT
    EXTRACT(HOUR FROM begintrip_at) AS local_hour,
    COUNT(*) AS trip_count,
    ROUND(AVG(original_fare_usd), 2) AS avg_fare
FROM trips
WHERE status = 'completed'
GROUP BY local_hour
HAVING COUNT(*) > 100          -- only "real" peak hours, not one-off noise
ORDER BY trip_count DESC;
-- Result: hours 23, 0, 22, 1, 2, 21 — six hours, all inside the
-- 21:00-02:00 night-shift window. HAVING just gave a precise,
-- reusable definition of "peak hour" instead of eyeballing the list.

-- HAVING can combine conditions like WHERE does:
SELECT
    status,
    COUNT(*) AS trip_count,
    ROUND(AVG(original_fare_usd), 2) AS avg_fare
FROM trips
GROUP BY status
HAVING COUNT(*) > 50 AND AVG(original_fare_usd) > 10;
-- Result: only 'completed' survives both filters — the two cancelled
-- statuses get excluded by the fare filter, not the count filter.


-- ----------------------------------------------------------------
-- LESSON 6: GROUP BY multiple columns — one group per COMBINATION
-- ----------------------------------------------------------------
-- Adding a second column to GROUP BY doesn't add more filtering —
-- it makes groups more specific: one row per (status, is_airport_trip)
-- pair that actually occurs in the data.

SELECT
    status,
    is_airport_trip,
    COUNT(*) AS trip_count,
    ROUND(AVG(original_fare_usd), 2) AS avg_fare
FROM trips
GROUP BY status, is_airport_trip
ORDER BY status, is_airport_trip;
-- Result: completed/non-airport = 3434 trips, $20.45 avg
--         completed/airport     =   17 trips, $36.12 avg  <- nearly 2x!
--         driver_canceled       =   41 trips, $6.04
--         rider_canceled        =  252 trips, $1.93 (+ 1 airport outlier, $5.00)
-- Insight: airport trips are a small slice of volume but a real
-- premium fare segment — worth a callout in any earnings story.


-- ----------------------------------------------------------------
-- WARM-UP FOR NEXT SESSION (run these first, mechanical recall only)
-- ----------------------------------------------------------------
-- 1) Count + avg fare by status, DESC by count (Lesson 2, from memory)
-- 2) Peak local hours using HAVING COUNT(*) > 100 (Lesson 5, from memory)


-- ────────────────────────────────────────────────────────────
-- NEXT SESSION: JOINs — INNER, LEFT, and the anti-join pattern
-- (NOT EXISTS / LEFT JOIN ... WHERE ... IS NULL)
-- Likely dataset: uber_analytics.trips + payments (or ratings) —
-- real multi-table joins instead of single-table grouping.
-- ────────────────────────────────────────────────────────────
