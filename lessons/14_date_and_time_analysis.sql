-- Lesson 14: Date and Time Analysis for Data Science
-- English reference notes. All statements are read-only and self-contained.
-- Execute one complete SELECT or WITH ... SELECT statement at a time.
-- VALUES creates query-local sample data, not permanent tables.
-- CTE definitions are repeated because they exist only within their statement.
-- Amounts below represent paid-order revenue, without refunds.


-- 01. Understand the time type and aggregate at daily grain.
-- DATE: a calendar date, without a time of day.
-- TIMESTAMP: a date and time without time-zone information.
-- TIMESTAMPTZ: an instant that can be represented in different time zones.
-- In TIMESTAMP examples below, values are already business-local clock times.
-- paid_at::date extracts the date; it does not change the source value.
-- GROUP BY changes the grain from one row per order to one row per active date.

WITH orders (order_id, paid_at, order_amount) AS (
    VALUES
        (1001, TIMESTAMP '2026-11-01 09:15:00',     100.00),
        (1002, TIMESTAMP '2026-11-01 23:59:59.500',  50.00),
        (1003, TIMESTAMP '2026-11-02 00:00:00',     100.00)
)
SELECT
    paid_at::date AS paid_date,
    COUNT(*) AS order_count,
    SUM(order_amount) AS daily_revenue
FROM orders
GROUP BY paid_at::date
ORDER BY paid_date;

-- Expected: November 1 -> 2 orders, 150; November 2 -> 1 order, 100.
-- GROUP BY does not generate dates absent from the input.


-- 02. Filter timestamps with a half-open interval: [start, end).
-- Include the start boundary and exclude the end boundary.
-- An upper bound of 23:59:59 misses timestamps such as 23:59:59.500.
-- BETWEEN includes both endpoints, so it is not the same as this range.
-- SQL requires two comparisons joined by AND, not a chained inequality.

WITH orders (order_id, paid_at, order_amount) AS (
    VALUES
        (1001, TIMESTAMP '2026-11-01 09:15:00',     100.00),
        (1002, TIMESTAMP '2026-11-01 23:59:59.500',  50.00),
        (1003, TIMESTAMP '2026-11-02 00:00:00',     100.00)
)
SELECT order_id, paid_at, order_amount
FROM orders
WHERE paid_at >= TIMESTAMP '2026-11-01 00:00:00'
  AND paid_at <  TIMESTAMP '2026-11-02 00:00:00'
ORDER BY paid_at, order_id;

-- Expected: orders 1001 and 1002, but not order 1003.
-- For all of November, use November 1 as the start and December 1 as the end.
-- Filtering a month does not itself aggregate the orders into a monthly total.


-- 03. Use DATE_TRUNC to assign timestamps to monthly buckets.
-- DATE_TRUNC('month', timestamp) returns the start of that timestamp's month.
-- It creates a bucket value; GROUP BY performs the aggregation.
-- A TIMESTAMP input produces a TIMESTAMP result, not a DATE or formatted string.

WITH orders (order_id, paid_at, order_amount) AS (
    VALUES
        (1001, TIMESTAMP '2026-11-01 09:15:00',     100.00),
        (1002, TIMESTAMP '2026-11-01 23:59:59.500',  50.00),
        (1003, TIMESTAMP '2026-11-02 00:00:00',     100.00),
        (1004, TIMESTAMP '2026-12-01 00:00:00',      80.00)
)
SELECT
    DATE_TRUNC('month', paid_at) AS paid_month,
    COUNT(*) AS order_count,
    SUM(order_amount) AS monthly_revenue
FROM orders
GROUP BY DATE_TRUNC('month', paid_at)
ORDER BY paid_month;

-- Expected: November -> 3 orders, 250; December -> 1 order, 80.


-- 04. The same instant can belong to different calendar dates.
-- The explicit +00 offset identifies the input instant in UTC.
-- For a TIMESTAMPTZ input, AT TIME ZONE returns a TIMESTAMP representing
-- the local clock time in the named zone. Then ::date extracts the local date.

SELECT
    TIMESTAMPTZ '2026-11-01 23:30:00+00'
        AT TIME ZONE 'UTC' AS utc_time,
    TIMESTAMPTZ '2026-11-01 23:30:00+00'
        AT TIME ZONE 'Europe/Luxembourg' AS luxembourg_time,
    (
        TIMESTAMPTZ '2026-11-01 23:30:00+00'
        AT TIME ZONE 'Europe/Luxembourg'
    )::date AS business_date;

-- Expected: UTC November 1 23:30; Luxembourg November 2 00:30;
-- business_date = November 2. These represent the SAME instant.
-- Important: AT TIME ZONE has different semantics for a TIMESTAMP input:
-- it interprets that local clock value in the specified zone, returning TIMESTAMPTZ.
-- Do not apply the TIMESTAMPTZ recipe blindly to a TIMESTAMP column.


-- 05. Define the business time zone before calculating daily revenue.
-- Here paid_at is TIMESTAMPTZ, unlike the business-local TIMESTAMP examples.
-- Convert to the business time zone first, then extract the date and group.

WITH orders (order_id, paid_at, order_amount) AS (
    VALUES
        (1001, TIMESTAMPTZ '2026-11-01 22:30:00+00', 100.00),
        (1002, TIMESTAMPTZ '2026-11-01 23:30:00+00',  50.00)
)
SELECT
    (paid_at AT TIME ZONE 'Europe/Luxembourg')::date AS business_date,
    COUNT(*) AS order_count,
    SUM(order_amount) AS daily_revenue
FROM orders
GROUP BY (paid_at AT TIME ZONE 'Europe/Luxembourg')::date
ORDER BY business_date;

-- Expected: November 1 -> 1 order, 100; November 2 -> 1 order, 50.
-- Replace the zone with 'UTC' in BOTH expressions to get November 1 -> 2, 150.
-- The time zone changes the daily allocation, not the total revenue.
-- Casting TIMESTAMPTZ directly to DATE uses the session time zone instead.


-- 06. A function can provide rows in FROM, just as a table can.
-- generate_series(start, stop, step) generates a sequence of values.
-- Parentheses here contain function arguments, not a nested SELECT query.

SELECT *
FROM generate_series(1, 3, 1);

-- Expected: three rows containing 1, 2, and 3.


-- 07. Generate a complete date spine.
-- A date spine provides one row for every date in the reporting period.
-- INTERVAL '1 day' is the step. The aligned endpoint is included here.
-- AS calendar(day_start): calendar is a table alias; day_start is a column alias.
-- This alias declaration is NOT another function call or a permanent table.
-- calendar.day_start references the generated column; ::date removes the time.

SELECT
    calendar.day_start::date AS calendar_date
FROM generate_series(
    TIMESTAMP '2026-11-01',
    TIMESTAMP '2026-11-03',
    INTERVAL '1 day'
) AS calendar(day_start)
ORDER BY calendar_date;

-- Expected: November 1, November 2, November 3.


-- 08. LEFT JOIN preserves dates without matching daily revenue records.
-- daily_revenue has at most one row per date, avoiding join fanout.
-- Missing matches produce NULL in r.revenue; the calendar date still exists.
-- COALESCE returns the first non-NULL argument and does not change stored data.
-- Only interpret missing revenue as zero when the source data is complete
-- and no orders truly means zero revenue. A data-loading failure is not zero.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-03',  50.00)
)
SELECT
    calendar.day_start::date AS calendar_date,
    r.revenue AS original_revenue,
    COALESCE(r.revenue, 0) AS revenue
FROM generate_series(
    TIMESTAMP '2026-11-01',
    TIMESTAMP '2026-11-03',
    INTERVAL '1 day'
) AS calendar(day_start)
LEFT JOIN daily_revenue AS r
    ON r.paid_date = calendar.day_start::date
ORDER BY calendar_date;

-- Expected: November 1 -> 100, 100; November 2 -> NULL, 0;
--           November 3 -> 50, 50.


-- 09. The denominator defines what an average means.
-- AVG ignores NULL inputs. Without filling the missing day, AVG uses two dates.
-- AVG(COALESCE(..., 0)) includes all three calendar dates in this complete dataset.
-- COALESCE(AVG(...), 0) would NOT include the missing day in the denominator.
-- Do not directly nest ordinary aggregates as AVG(SUM(revenue)).
-- The input is already daily totals: simply average those daily values.

WITH daily_revenue (paid_date, revenue) AS (
    VALUES
        (DATE '2026-11-01', 100.00),
        (DATE '2026-11-03',  50.00)
)
SELECT
    AVG(r.revenue) AS average_on_dates_with_orders,
    AVG(COALESCE(r.revenue, 0)) AS average_daily_revenue
FROM generate_series(
    TIMESTAMP '2026-11-01',
    TIMESTAMP '2026-11-03',
    INTERVAL '1 day'
) AS calendar(day_start)
LEFT JOIN daily_revenue AS r
    ON r.paid_date = calendar.day_start::date;

-- Expected: 75 = 150 / 2 versus 50 = 150 / 3.
-- This overall summary returns one row, so do not also select each date.
-- Grouping by date would calculate separate daily averages, not one period average.


-- 10. Complete pipeline: raw orders -> daily totals -> complete calendar.
-- Aggregate first to guarantee one daily_revenue row per matching date.
-- Separate CTE definitions with commas; use one WITH for this statement.

WITH orders (order_id, paid_at, order_amount) AS (
    VALUES
        (1001, TIMESTAMP '2026-11-01 09:00:00', 60.00),
        (1002, TIMESTAMP '2026-11-01 15:00:00', 40.00),
        (1003, TIMESTAMP '2026-11-03 10:00:00', 50.00)
),
daily_revenue AS (
    SELECT
        paid_at::date AS paid_date,
        SUM(order_amount) AS revenue
    FROM orders
    GROUP BY paid_at::date
)
SELECT
    calendar.day_start::date AS calendar_date,
    COALESCE(r.revenue, 0) AS revenue
FROM generate_series(
    TIMESTAMP '2026-11-01',
    TIMESTAMP '2026-11-03',
    INTERVAL '1 day'
) AS calendar(day_start)
LEFT JOIN daily_revenue AS r
    ON r.paid_date = calendar.day_start::date
ORDER BY calendar_date;

-- Expected: November 1 -> 100; November 2 -> 0; November 3 -> 50.
-- These orders total 150, unlike the earlier monthly example totaling 330.


-- 11. Define the last seven COMPLETE calendar days, excluding the report date.
-- DATE minus an integer subtracts that many calendar days.
-- Explicit report dates make historical results reproducible.

SELECT
    DATE '2026-11-05' AS report_date,
    DATE '2026-11-05' - 7 AS start_date,
    DATE '2026-11-05' AS end_date_exclusive;

-- Expected range: October 29 at midnight <= paid_at < November 5 at midnight.
-- This includes October 29 through November 4, exactly seven calendar dates.
-- It is not a rolling window ending at the current time of day.
-- Calendar-day windows are not necessarily fixed 168-hour windows across DST.


-- 12. Use CURRENT_DATE for a dynamic reporting date.
-- CURRENT_DATE is based on transaction start, interpreted in the session time zone.
-- Its value does not advance at midnight inside the same long-running transaction.
-- Ensure the reporting date and session time zone match the business definition.

SELECT
    CURRENT_DATE AS report_date,
    CURRENT_DATE - 7 AS start_date,
    CURRENT_DATE AS end_date_exclusive;

-- On November 5, 2026: report date November 5; start October 29; end November 5.
-- For the business-local TIMESTAMP examples, the filtering predicate is:
-- WHERE paid_at >= CURRENT_DATE - 7
--   AND paid_at < CURRENT_DATE
-- DATE boundaries are interpreted at midnight when compared with TIMESTAMP.
-- For TIMESTAMPTZ data, do not rely on implicit session-zone boundaries unless
-- the session zone matches the business zone; use explicitly defined instants.


-- 13. Date-series endpoints differ from exclusive timestamp-filter boundaries.
-- generate_series includes an aligned endpoint: stop at YESTERDAY, not today.
-- ::timestamp turns each DATE boundary into a local midnight TIMESTAMP.

SELECT
    day_start::date AS calendar_date
FROM generate_series(
    (CURRENT_DATE - 7)::timestamp,
    (CURRENT_DATE - 1)::timestamp,
    INTERVAL '1 day'
) AS calendar(day_start)
ORDER BY calendar_date;

-- On November 5, 2026: seven rows from October 29 through November 4.
-- A stop value of CURRENT_DATE would also include today, producing eight rows.


-- 14. DS date-analysis checklist.
-- Define the source time type, business time zone, and reporting grain.
-- Specify whether the window includes today and whether today is complete.
-- Use >= start AND < end for adjacent timestamp ranges without overlap.
-- Convert instants to the business time zone before extracting dates/buckets.
-- Aggregate raw events to daily grain before joining a daily date spine.
-- Distinguish absent records, true zero activity, and incomplete data loads.
-- Include all required calendar dates in average-per-day denominators.
-- Use the correct inclusive endpoint when generating calendar rows.
-- Execute a complete statement beginning with SELECT or WITH, not an isolated
-- TIMESTAMPTZ literal, function argument, or CTE definition.

-- PostgreSQL 18 references:
-- https://www.postgresql.org/docs/18/functions-datetime.html
-- https://www.postgresql.org/docs/18/functions-srf.html
-- https://www.postgresql.org/docs/18/functions-aggregate.html
-- https://www.postgresql.org/docs/18/functions-conditional.html
