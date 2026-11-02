-- Lesson 10: Pagination (PostgreSQL 18)
-- Execute one complete statement at a time. Executable queries are read-only.
-- Uses the existing lab_index_employees table from Lesson 09: 100,000 rows.
-- No setup, inserts, deletes, or index changes are needed for these notes.
-- Sample VALUES rows are query-local; they do not modify the lab table.
-- Plans and timings below are historical observations, not guaranteed results.


-- 01. LIMIT and OFFSET: fetch a page by skipping positions.
-- LIMIT is the maximum number of rows returned; fewer rows are possible.
-- OFFSET is the number of ordered rows to skip, NOT an ID or a page number.
-- For page numbers starting at 1:
-- offset = (page_number - 1) * page_size.
-- Use a unique ORDER BY for predictable page boundaries.

-- Page 1: IDs 1-5 in our unchanged lab data.
SELECT id, name, department_id
FROM lab_index_employees
ORDER BY id
LIMIT 5 OFFSET 0;

-- Page 2: IDs 6-10.
SELECT id, name, department_id
FROM lab_index_employees
ORDER BY id
LIMIT 5 OFFSET 5;

-- Page 3: IDs 11-15.
SELECT id, name, department_id
FROM lab_index_employees
ORDER BY id
LIMIT 5 OFFSET 10;


-- 02. Deep pagination: an index does not make a large OFFSET free.
-- Observed: Limit returned 5 rows; the primary-key Index Scan output 90,005 rows.
-- OFFSET discarded the first 90,000 rows produced by that scan.
-- Shared buffer accesses: 3 hits + 818 reads; Execution Time: 22.126 ms.

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
ORDER BY id
LIMIT 5 OFFSET 90000;


-- 03. Keyset pagination: continue after the last seen key.
-- Assume the previous page's last ID was 90000.
-- This cursor is a key value, not a count of rows already displayed.
-- Gaps in IDs do not break the approach.

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE id > 90000
ORDER BY id
LIMIT 5;

-- Observed: Index Cond: (id > 90000); actual scan output: 5 rows.
-- Shared buffer accesses: 3 hits; Execution Time: 0.031 ms.
-- The index located the starting range; LIMIT stopped retrieval after 5 rows.
-- Estimated rows=9858 described the estimated range if consumed fully,
-- not how many rows this limited execution actually returned.
-- The two experiments had different cache conditions: timings alone are not proof
-- of a fixed speedup. The scan output counts show the difference in work.
-- Equal results here rely on the current consecutive IDs: OFFSET 90000 and
-- id > 90000 are NOT generally equivalent when IDs have gaps.

-- If that page ends at ID 90005, update the cursor for the next page.
SELECT id, name, department_id
FROM lab_index_employees
WHERE id > 90005
ORDER BY id
LIMIT 5;


-- 04. The cursor comparison must match the sort direction.
-- Ascending: continue with greater keys (>).
-- Descending: continue with smaller keys (<).
-- Use strict comparisons: >= or <= can repeat the previous page's final row.

SELECT id, name, department_id
FROM lab_index_employees
WHERE id < 90005
ORDER BY id DESC
LIMIT 5;


-- 05. Repeated sort values need a unique tie-breaker.
-- Sample order: Alex(101), Alex(105), Alex(108), Bob(120).
-- After page 1 ends at Alex(105), name > 'Alex' would skip Alex(108).
-- Instead, keep BOTH name and id in the ordering and in the cursor.
-- Expanded condition:
-- WHERE name > 'Alex' OR (name = 'Alex' AND id > 105).
-- For non-NULL values with both keys ascending, row comparison is a shorthand.
-- Compare name first; only equal names require comparing id.

WITH sample (id, name) AS (
    VALUES (101, 'Alex'), (105, 'Alex'), (108, 'Alex'), (120, 'Bob')
)
SELECT id, name
FROM sample
WHERE (name, id) > ('Alex', 105)
ORDER BY name, id
LIMIT 2;

-- Expected: Alex(108), Bob(120).
-- If the previous page instead ends at Alex(108), replace BOTH cursor values
-- with ('Alex', 108). Never keep using an older page's cursor.


-- 06. Real composite-cursor practice: page 1.
-- name is text, not a numeric employee number. Ordering follows its collation.
-- Observed IDs: 1, 10, 100, 1000, 10000.
-- Last row: name = 'Employee 10000', id = 10000.

SELECT id, name
FROM lab_index_employees
ORDER BY name, id
LIMIT 5;

-- Page 2: continue after the exact last (name, id) pair from page 1.
SELECT id, name
FROM lab_index_employees
WHERE (name, id) > ('Employee 10000', 10000)
ORDER BY name, id
LIMIT 5;

-- Observed IDs: 100000, 10001, 10002, 10003, 10004.
-- 'Employee 100000' is a different name, ordered AFTER 'Employee 10000'
-- in our lab and BEFORE 'Employee 10001'. It is not a repeated row.
-- Do not replace the composite condition with id > 10000:
-- the primary ordering is by name, not numeric ID.

-- Page 3: page 2's last row is Employee 10004, ID 10004.
SELECT id, name
FROM lab_index_employees
WHERE (name, id) > ('Employee 10004', 10004)
ORDER BY name, id
LIMIT 5;

-- Observed IDs: 10005, 10006, 10007, 10008, 10009.
-- For a real application, derive the next cursor from the returned last row,
-- rather than hard-coding these example values or adding the page size to an ID.


-- 07. Ordering, cursor, and index design must agree.
-- All examples use NOT NULL keys. Nullable keys require an explicit NULL policy;
-- a row comparison can return UNKNOWN when it reaches a NULL pair.
-- For mixed directions, such as name ASC, id DESC, a simple tuple > is not
-- the correct general continuation condition. Handle each direction explicitly.
-- A cursor alone does not ensure efficiency: check the supporting index and plan.

/* Design reference only; this index was NOT created during Lesson 10:
CREATE INDEX example_name_id_pagination_idx
ON lab_index_employees (name, id);
*/

-- This key order naturally matches the global ORDER BY name, id query.
-- Existing (department_id, name) ordering is not the same as global name, id.
-- INCLUDE(id) supplies a value but does not provide id tie-breaker ordering.
-- Avoid creating overlapping indexes without measuring the actual workload.


-- 08. Choosing a pagination method.
-- OFFSET: compute an offset from a page number; convenient for arbitrary jumps.
-- Keyset: needs an actual cursor; well suited to next-page / load-more requests.
-- Page number 100 alone does not reveal its starting (name, id) pair.
-- Keyset can efficiently seek when a suitable index supports the query.


-- 09. Concurrent changes can shift OFFSET page boundaries.
-- These are hypothetical examples, NOT instructions to modify lab data.
-- Assume each later query sees the committed change, as with Read Committed.
-- Initial IDs: 10, 20, 30, 40. Page 1 (size 2) returns 10, 20.
--
-- Insert 15 before fetching page 2:
-- Current order: 10, 15, 20, 30, 40.
-- OFFSET 2 LIMIT 2 returns 20, 30: ID 20 repeats.
-- WHERE id > 20 ORDER BY id LIMIT 2 returns 30, 40.
-- Newly inserted ID 15 is before the cursor, so this traversal does not show it.
--
-- Separately, delete 10 from the INITIAL data before fetching page 2:
-- Current order: 20, 30, 40.
-- OFFSET 2 LIMIT 2 returns only 40: unseen ID 30 is skipped.
-- WHERE id > 20 ORDER BY id LIMIT 2 still returns 30, 40.


-- 10. Keyset pagination is NOT a fixed snapshot.
-- It avoids the demonstrated position shifts when earlier rows are inserted/deleted.
-- It does not freeze the dataset across independent page queries.
-- Updating ordering keys can move rows across a cursor and cause omissions/repeats.
-- Changes to query filters can also change which rows qualify.
-- A stable cross-page view requires a separate snapshot/consistency design.
-- Keep filters, key order, comparison direction, and cursor values consistent.

-- Core summary:
-- OFFSET tracks positions; keyset pagination tracks key values.
-- Use a unique ordering and update the cursor from each page's last row.
-- With a suitable index, keyset avoids processing a large skipped prefix.
-- Neither method automatically freezes data across requests.

-- PostgreSQL 18 reference documentation:
-- https://www.postgresql.org/docs/18/queries-limit.html
-- https://www.postgresql.org/docs/18/functions-comparisons.html#ROW-WISE-COMPARISON
-- https://www.postgresql.org/docs/18/transaction-iso.html
-- https://www.postgresql.org/docs/18/indexes-ordering.html
