-- Lesson 16: User Deduplication and Conversion Metrics for Data Science
-- English reference notes. All statements are read-only and self-contained.
-- Execute one complete SELECT or WITH ... SELECT statement at a time.
-- VALUES creates query-local sample data, not permanent tables or inserted events.
-- CTEs exist only within their statement, so definitions are repeated below.
-- Sample stages use different events to isolate individual metric concepts.
-- TIMESTAMP values are already business-local times; for TIMESTAMPTZ sources,
-- convert to the business time zone before extracting dates (see Lesson 14).
-- Assume complete sample data. Missing ingestion is not proof of zero activity.


-- 01. Event count and active-user count measure different entities.
-- Grain: one input row per event, not one per user.
-- In this first sample, all events occur on the same business date and qualify
-- as activity. A user is active if they generate at least one qualifying event.
-- DAU = Daily Active Users: count each qualifying user once per business date.

WITH events (event_id, user_id, event_at) AS (
    VALUES
        (1, 101, TIMESTAMP '2026-11-01 09:00:00'),
        (2, 101, TIMESTAMP '2026-11-01 09:05:00'),
        (3, 102, TIMESTAMP '2026-11-01 10:00:00'),
        (4, 103, TIMESTAMP '2026-11-01 11:00:00')
)
SELECT
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS daily_active_users
FROM events;

-- Expected: 4 events, 3 active users. User 101's two events count as one user.
-- Without a daily grouping or single-date filter, this would be a period count,
-- not necessarily DAU. Here all sample events belong to one date.


-- 02. Calculate DAU separately within each date.
-- GROUP BY date creates daily groups; DISTINCT deduplicates IDs within each group.
-- The same user can contribute once to each of several different dates.

WITH events (event_id, user_id, event_at) AS (
    VALUES
        (1, 101, TIMESTAMP '2026-11-01 09:00:00'),
        (2, 101, TIMESTAMP '2026-11-01 09:05:00'),
        (3, 102, TIMESTAMP '2026-11-01 10:00:00'),
        (4, 103, TIMESTAMP '2026-11-01 11:00:00'),
        (5, 101, TIMESTAMP '2026-11-02 09:00:00'),
        (6, 104, TIMESTAMP '2026-11-02 10:00:00')
)
SELECT
    event_at::date AS activity_date,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS daily_active_users
FROM events
GROUP BY event_at::date
ORDER BY activity_date;

-- Expected: November 1 -> 4 events, 3 users; November 2 -> 2 events, 2 users.


-- 03. Daily distinct counts cannot generally be summed into period distinct users.
-- User 101 appears on both dates: count once per day, but once across the period.

WITH events (event_id, user_id, event_at) AS (
    VALUES
        (1, 101, TIMESTAMP '2026-11-01 09:00:00'),
        (2, 101, TIMESTAMP '2026-11-01 09:05:00'),
        (3, 102, TIMESTAMP '2026-11-01 10:00:00'),
        (4, 103, TIMESTAMP '2026-11-01 11:00:00'),
        (5, 101, TIMESTAMP '2026-11-02 09:00:00'),
        (6, 104, TIMESTAMP '2026-11-02 10:00:00')
)
SELECT
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS period_active_users
FROM events;

-- Expected: 6 events, 4 distinct users (101, 102, 103, 104).
-- Sum of DAU = 3 + 2 = 5 active user-days, not 5 distinct users or 5 events.
-- Define the reporting window before naming a count DAU, WAU, or MAU.


-- 04. Define qualifying activity before counting active users.
-- Business definition for this single-day sample: page_view and click qualify;
-- heartbeat is an automatic background event and does not qualify.
-- This is an example definition, not a universal rule for all products.

WITH events (event_id, user_id, event_name) AS (
    VALUES
        (1, 101, 'page_view'),
        (2, 101, 'click'),
        (3, 102, 'page_view'),
        (4, 103, 'heartbeat')
)
SELECT
    COUNT(*) AS qualifying_event_count,
    COUNT(DISTINCT user_id) AS daily_active_users
FROM events
WHERE event_name IN ('page_view', 'click');

-- Expected: 3 qualifying events, 2 active users. User 103 is excluded.
-- WHERE selects qualifying events before aggregation and user deduplication.


-- 05. COUNT variants, unknown identity, and event-level identification coverage.
-- COUNT(*) counts rows, including events whose user_id is NULL.
-- COUNT(user_id) counts non-NULL IDs, including repeated IDs on different rows.
-- COUNT(DISTINCT user_id) counts distinct non-NULL IDs.
-- An event without a known user ID still exists, but its user cannot be deduplicated.

WITH events (event_id, user_id, event_name) AS (
    VALUES
        (1, 101, 'page_view'),
        (2, 101, 'click'),
        (3, 102, 'page_view'),
        (4, 103, 'heartbeat'),
        (5, NULL, 'page_view')
)
SELECT
    COUNT(*) AS qualifying_event_count,
    COUNT(user_id) AS identified_event_count,
    COUNT(DISTINCT user_id) AS identified_active_users,
    COUNT(*) - COUNT(user_id) AS unidentified_event_count,
    100.0 * COUNT(user_id)
        / NULLIF(COUNT(*), 0) AS identification_coverage_pct
FROM events
WHERE event_name IN ('page_view', 'click');

-- Expected: 4 qualifying events, 3 identified events, 2 identified users,
-- 1 unidentified event, identification coverage 75%.
-- Filtered IDs are 101, 101, 102, NULL: COUNT(*) = 4, COUNT(id) = 3, DISTINCT = 2.
-- Coverage is a percentage of EVENTS, not a percentage of all real users identified.
-- An unknown-ID event may belong to an already observed user or another user.
-- Do not assume one anonymous event means one additional distinct person.
-- Do not COALESCE every unknown user ID to one shared ID and call it a real user.
-- With no qualifying events, the counts are zero and coverage is NULL, not 0%.


-- 06. User-level conversion begins with user-level action flags.
-- Definition: among users who viewed a page on a date, what share also purchased
-- on that date? Repeated purchases do not create additional converted users.
-- This metric requires same-day co-occurrence, NOT view-before-purchase ordering.
-- It is not yet an ordered funnel or a multi-day attribution metric.
-- All events in this sample belong to one business date.
-- Use known user IDs for user-level metrics; monitor unknown events separately.

WITH events (event_id, user_id, event_name) AS (
    VALUES
        (1, 101, 'page_view'),
        (2, 101, 'purchase'),
        (3, 101, 'purchase'),
        (4, 102, 'page_view'),
        (5, 103, 'page_view')
)
SELECT
    user_id,
    MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS has_page_view,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
FROM events
WHERE user_id IS NOT NULL
GROUP BY user_id
ORDER BY user_id;

-- Expected (user_id, has_page_view, has_purchase): (101, 1, 1), (102, 1, 0), (103, 1, 0).
-- CASE maps events to 1/0; MAX becomes 1 if any event meets the condition.
-- User 101's two purchases still produce has_purchase = 1, not 2.
-- Grain changes from one row per event to one row per identified user.


-- 07. Restrict the conversion numerator to the denominator's eligible population.
-- Add user 104 with a purchase but no page_view in the reporting date.
-- This does not mean the user has never viewed a page, only that this sample
-- contains no qualifying view for that user in the defined reporting window.
-- Numerator: viewing users who purchased. Denominator: viewing users.

WITH events (event_id, user_id, event_name) AS (
    VALUES
        (1, 101, 'page_view'),
        (2, 101, 'purchase'),
        (3, 101, 'purchase'),
        (4, 102, 'page_view'),
        (5, 103, 'page_view'),
        (6, 104, 'purchase')
),
user_activity AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS has_page_view,
        MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM events
    WHERE user_id IS NOT NULL
    GROUP BY user_id
)
SELECT
    COUNT(*) AS viewing_users,
    COALESCE(SUM(has_purchase), 0) AS converted_users,
    100.0 * COALESCE(SUM(has_purchase), 0)
        / NULLIF(COUNT(*), 0) AS user_conversion_pct
FROM user_activity
WHERE has_page_view = 1;

-- Expected: 3 viewing users, 1 converted user, approximately 33.33% conversion.
-- User 104 is excluded by has_page_view = 1: adding that purchase changes neither count.
-- COUNT(*) now counts users because the CTE already has one row per user.
-- SUM(has_purchase) adds user-level 1/0 flags; it does not count purchase events.
-- 100.0 provides decimal arithmetic. NULLIF prevents division by zero.
-- If no users qualify, this overall aggregate still returns one row:
-- viewing_users = 0, converted_users = 0, user_conversion_pct = NULL.


-- 08. For multiple dates, construct one row per USER PER DATE.
-- Grouping only by user_id could combine a November 1 view with a November 2
-- purchase and incorrectly count a same-day conversion.
-- Date and identity together define the intermediate grain.

WITH events (event_id, user_id, event_at, event_name) AS (
    VALUES
        (1, 101, TIMESTAMP '2026-11-01 09:00:00', 'page_view'),
        (2, 101, TIMESTAMP '2026-11-02 10:00:00', 'purchase'),
        (3, 102, TIMESTAMP '2026-11-01 11:00:00', 'page_view'),
        (4, 102, TIMESTAMP '2026-11-01 11:10:00', 'purchase'),
        (5, 103, TIMESTAMP '2026-11-02 12:00:00', 'page_view')
)
SELECT
    event_at::date AS activity_date,
    user_id,
    MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS has_page_view,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
FROM events
WHERE user_id IS NOT NULL
GROUP BY event_at::date, user_id
ORDER BY activity_date, user_id;

-- Expected (date, user, view, purchase):
-- November 1: (101, 1, 0), (102, 1, 1).
-- November 2: (101, 0, 1), (103, 1, 0).
-- User 101's November 2 purchase is not a November 1 same-day conversion.


-- 09. Aggregate user-day records into daily conversion metrics.
-- Events -> user-day flags -> eligible viewing users -> daily counts and rate.
-- SQL can execute successfully while using the wrong business definition:
-- forgetting WHERE has_page_view = 1 would include purchase-only users.

WITH events (event_id, user_id, event_at, event_name) AS (
    VALUES
        (1, 101, TIMESTAMP '2026-11-01 09:00:00', 'page_view'),
        (2, 101, TIMESTAMP '2026-11-02 10:00:00', 'purchase'),
        (3, 102, TIMESTAMP '2026-11-01 11:00:00', 'page_view'),
        (4, 102, TIMESTAMP '2026-11-01 11:10:00', 'purchase'),
        (5, 103, TIMESTAMP '2026-11-02 12:00:00', 'page_view')
),
user_daily_activity AS (
    SELECT
        event_at::date AS activity_date,
        user_id,
        MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS has_page_view,
        MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM events
    WHERE user_id IS NOT NULL
    GROUP BY event_at::date, user_id
)
SELECT
    activity_date,
    COUNT(*) AS viewing_users,
    COALESCE(SUM(has_purchase), 0) AS converted_users,
    100.0 * COALESCE(SUM(has_purchase), 0)
        / NULLIF(COUNT(*), 0) AS user_conversion_pct
FROM user_daily_activity
WHERE has_page_view = 1
GROUP BY activity_date
ORDER BY activity_date;

-- Expected: November 1 -> 2 viewers, 1 converted, 50%; November 2 -> 1, 0, 0%.
-- Without the eligibility WHERE, November 2 would incorrectly report 2, 1, 50%.
-- A date with no eligible viewers produces NO GROUP and is absent from this output.
-- COALESCE inside an aggregate SELECT does not generate a missing date group.


-- 10. Zero conversion, undefined conversion, and missing output rows differ.
-- 0%: eligible viewers exist, but none purchased (0 / positive denominator).
-- NULL: no eligible viewers, so the rate is undefined (zero denominator).
-- Missing row: no group was produced; this does not itself display either value.
-- Integration example combining Lessons 14 and 16: add November 3 with only a
-- purchase by user 104, then preserve all reporting dates using a date spine.
-- Assume complete data before interpreting an absent viewer group as zero viewers.

WITH events (event_id, user_id, event_at, event_name) AS (
    VALUES
        (1, 101, TIMESTAMP '2026-11-01 09:00:00', 'page_view'),
        (2, 101, TIMESTAMP '2026-11-02 10:00:00', 'purchase'),
        (3, 102, TIMESTAMP '2026-11-01 11:00:00', 'page_view'),
        (4, 102, TIMESTAMP '2026-11-01 11:10:00', 'purchase'),
        (5, 103, TIMESTAMP '2026-11-02 12:00:00', 'page_view'),
        (6, 104, TIMESTAMP '2026-11-03 09:00:00', 'purchase')
),
user_daily_activity AS (
    SELECT
        event_at::date AS activity_date,
        user_id,
        MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS has_page_view,
        MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM events
    WHERE user_id IS NOT NULL
    GROUP BY event_at::date, user_id
),
daily_conversion AS (
    SELECT
        activity_date,
        COUNT(*) AS viewing_users,
        SUM(has_purchase) AS converted_users,
        100.0 * SUM(has_purchase)
            / NULLIF(COUNT(*), 0) AS user_conversion_pct
    FROM user_daily_activity
    WHERE has_page_view = 1
    GROUP BY activity_date
)
SELECT
    calendar.day_start::date AS activity_date,
    COALESCE(d.viewing_users, 0) AS viewing_users,
    COALESCE(d.converted_users, 0) AS converted_users,
    d.user_conversion_pct
FROM generate_series(
    TIMESTAMP '2026-11-01',
    TIMESTAMP '2026-11-03',
    INTERVAL '1 day'
) AS calendar(day_start)
LEFT JOIN daily_conversion AS d
    ON d.activity_date = calendar.day_start::date
ORDER BY activity_date;

-- Expected: November 1 -> 2, 1, 50%; November 2 -> 1, 0, 0%; November 3 -> 0, 0, NULL.
-- Join the pre-aggregated daily metrics, preserving one row per reporting date.
-- Counts can be displayed as zero; do not COALESCE an undefined conversion rate to 0%.


-- 11. DS metric-definition checklist.
-- Define the entity counted: events, identified users, or active user-days.
-- Define the business date/time zone and the reporting window.
-- Specify which observed events qualify as activity or conversion.
-- Handle unknown identity explicitly; event coverage does not prove user coverage.
-- Choose a grouping grain that matches the question (user versus user-date).
-- Keep numerator users within the denominator's eligible population and time window.
-- Separate same-day action co-occurrence from an ordered conversion funnel.
-- Deduplicate users before counting user conversions; repeated events are not new users.
-- Preserve the distinction between a known zero, an undefined rate, and a missing row.
-- Check both data completeness and metric logic, not just whether SQL executes.

-- PostgreSQL 18 references:
-- https://www.postgresql.org/docs/18/functions-aggregate.html
-- https://www.postgresql.org/docs/18/sql-expressions.html#SYNTAX-AGGREGATES
-- https://www.postgresql.org/docs/18/functions-conditional.html
-- https://www.postgresql.org/docs/18/queries-table-expressions.html
-- https://www.postgresql.org/docs/18/functions-srf.html
