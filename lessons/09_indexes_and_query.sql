-- Lesson 09: Indexes and Query Plans (PostgreSQL 18)
-- English reference notes: execute one complete statement at a time.
-- Executable statements below are read-only SELECT / EXPLAIN SELECT queries.
-- Setup, statistics maintenance, and index creation are commented out.
-- Do not repeat the setup: the lab table and practice indexes already exist.
-- Historical plans describe the indexes available at that experiment's stage;
-- plans may differ now because we added more indexes during the lesson.


-- 01. Indexes provide access paths; the optimizer chooses whether to use them.
-- An index can reduce data accessed without changing the matching result set.
-- Indexes consume storage and add maintenance overhead to writes.
-- Create indexes for actual WHERE, JOIN, and ORDER BY requirements, not every column.
-- CREATE INDEX uses B-tree by default. A normal index permits duplicate values.
-- PRIMARY KEY and UNIQUE constraints create unique indexes automatically.
-- A foreign key does not automatically index its referencing column in PostgreSQL.

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('departments', 'employees', 'lab_index_employees')
ORDER BY tablename, indexname;


-- 02. EXPLAIN shows estimates; EXPLAIN ANALYZE actually executes the statement.
-- Never treat EXPLAIN ANALYZE UPDATE / DELETE / INSERT as a harmless preview.

EXPLAIN
SELECT id, name, department_id
FROM employees
WHERE id = 101;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM employees
WHERE department_id = 1;

-- Reading the output:
-- cost=a..b: estimated startup and total cost; these are NOT milliseconds.
-- rows before actual: estimated output rows, not rows examined.
-- width: estimated average output row size in bytes.
-- actual time=a..b: measured startup and total node time in milliseconds.
-- actual rows: output rows per execution, averaged when loops > 1.
-- loops: how many times the node ran; all our displayed scan examples used 1.
-- Planning Time and Execution Time describe different phases.
-- Parent node times include child work; do not add them as independent durations.
-- Compare the same query and result set; single-run timings are not a benchmark.


-- 03. ANALYZE refreshes optimizer statistics; it is not EXPLAIN ANALYZE.
-- It does not change employee business values.
-- Better statistics can improve estimates without making an index desirable.
-- On our three-row employees table, scanning two matching rows was inexpensive.

/* Maintenance / creation examples already performed in the lesson:
ANALYZE employees;

CREATE INDEX employees_department_id_idx
ON employees (department_id);
-- In Manual commit mode, commit intentional changes after checking them.
COMMIT;
*/


-- 04. Large-table experiment: setup reference, NOT a task to repeat.
-- 100,000 employees; 1,000 department values; 100 employees per department.
-- department_id is synthetic and has no foreign key to departments.
-- generate_series supplies numbers; || concatenates text; % is modulo.

/* Run only when deliberately rebuilding the experiment in a fresh environment:
CREATE TABLE lab_index_employees (
    id integer PRIMARY KEY,
    name text NOT NULL,
    department_id integer NOT NULL
);

INSERT INTO lab_index_employees (id, name, department_id)
SELECT n, 'Employee ' || n, (n % 1000) + 1
FROM generate_series(1, 100000) AS numbers(n);
COMMIT;

ANALYZE lab_index_employees;
*/


-- 05. A selective department query: sequential scan versus bitmap access.
-- Before the department index: Seq Scan returned 100 rows and filtered out 99,900.
-- After creating it: Bitmap Index Scan found locations; Bitmap Heap Scan read rows.
-- Heap means table storage, not heap sort. The index itself is still a B-tree.

/* Already created; do not recreate:
CREATE INDEX lab_index_employees_department_id_idx
ON lab_index_employees (department_id);
COMMIT;
*/

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE department_id = 42;

-- Historical observations for this identical query:
-- Before: 637 shared hits; Execution Time 6.268 ms.
-- After: 100 shared hits + 2 shared reads; Execution Time 0.199 ms.
-- Returned rows remained 100. Less data access was the main improvement.
-- Heap Blocks: exact=100 counts exact heap pages, NOT returned rows.
-- Recheck Cond identifies a condition for possible bitmap heap rechecking;
-- its presence does not imply a full table rescan or an incorrect index.

-- BUFFERS essentials:
-- shared hit: a block was already in PostgreSQL's shared buffer cache.
-- shared read: a block was loaded there; the OS may still have cached it.
-- Counts are block accesses, not necessarily distinct blocks or physical disk I/O.
-- Parent buffer figures include child figures: do not count them twice.


-- 06. Having an index does not mean that using it is cheapest.
-- This predicate matches all 100,000 rows in our dataset.
-- Observed: Seq Scan, 100,000 output rows, 637 shared hits.
-- Small tables and large matching fractions often favor sequential scans.

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE department_id >= 1;


-- 07. A query can filter by a column even without a suitable index.
-- Before the name index: Seq Scan found 1 row and filtered out 99,999.
-- Finding one match did not stop that scan: name is not constrained to be unique.
-- After the name index: Index Scan used name equality as its Index Cond.

/* Already created; do not recreate:
CREATE INDEX lab_index_employees_name_idx
ON lab_index_employees (name);
COMMIT;
*/

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE name = 'Employee 500';

-- Observed before / after: 637 shared hits / 1 hit + 3 reads.
-- Measured Execution Time: 4.929 ms / 0.141 ms; not a guaranteed speedup.


-- 08. Index Cond locates candidates; Filter checks retrieved candidates.
-- A plain name B-tree does not normally narrow a leading-wildcard contains search.
-- PostgreSQL may display LIKE as ~~ and text literals with ::text casts.

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE department_id = 42
  AND name LIKE '%500%';

-- Observed with the department index:
-- Index Cond: department_id = 42 -> 100 candidate rows.
-- Filter: name LIKE '%500%' -> 99 rejected; 1 returned.
-- Rows Removed by Filter counts rejections at THAT node, not across the whole table.
-- Other departments did not reach this name filter.
-- A Filter can coexist with efficient index access; it is not automatically bad.


-- 09. Composite indexes contain multiple key columns in a defined order.
-- (department_id, name): department first; name within each department.
-- Both equality predicates participated in our observed Index Cond.

/* Already created; do not recreate:
CREATE INDEX lab_index_employees_department_name_idx
ON lab_index_employees (department_id, name);
COMMIT;
*/

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE department_id = 42
  AND name = 'Employee 50041';

-- Leading-column equality is a natural way to narrow a composite B-tree scan.
-- This index also supports department-only lookups; the planner may choose another.
-- For these two equality conditions, either key order can use both conditions.
-- Do not claim that omitting the leading column ALWAYS prevents index use:
-- PostgreSQL 18 can sometimes use skip scan. Inspect the actual plan instead.


-- 10. An index can support both filtering and ordering.
-- With department fixed, (department_id, name) supplies name order.
-- Observed: Limit -> Index Scan, no separate Sort, only 5 scan output rows.
-- A matching ordered scan can stop early instead of fetching every department row.

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, department_id
FROM lab_index_employees
WHERE department_id = 42
ORDER BY name
LIMIT 5;

-- Removing LIMIT returns all 100 department rows, still ordered by name.
-- Removing ORDER BY leaves the choice/order of five rows unspecified.
-- An existing index never replaces an explicit ORDER BY requirement.


-- 11. Deterministic ordering requires a tie-breaker when names can repeat.
-- ASC is the default. For equal names, id ASC puts 105 before 108.
-- ORDER BY name ASC, id DESC would put 108 first among those same-name rows.

SELECT id, name, department_id
FROM lab_index_employees
WHERE department_id = 42
ORDER BY name, id
LIMIT 5;

-- (department_id, name) alone does not supply the id tie-breaker order;
-- an additional sorting step may be needed.
-- With department fixed, (department_id, name, id) supplies name, id order.
-- It does NOT directly supply id, name order: key sequence matters.
-- For id, name ordering, (department_id, id, name) matches the requested sequence.
-- Since id is unique here, name cannot break any id ties; (department_id, id)
-- already supplies that order. Carrying name is a separate coverage decision.


-- 12. Index Only Scan: requested values can come directly from the index.
-- Both selected columns below are in (department_id, name).
-- PostgreSQL still checks MVCC visibility, using the visibility map when possible.
-- Otherwise it must visit heap tuples: Index Only Scan does not guarantee zero.

EXPLAIN (ANALYZE, BUFFERS)
SELECT department_id, name
FROM lab_index_employees
WHERE department_id = 42
ORDER BY name
LIMIT 5;

-- Observed: Index Only Scan, Heap Fetches: 0, shared hit=4.
-- Heap Fetches: 0 means no heap tuple fetches, not zero buffer accesses.
-- Adding id requires a value absent from this index; an ordinary Index Scan
-- must fetch it from the table. PostgreSQL secondary indexes do not automatically
-- include the primary-key value just because a primary key exists.


-- 13. Covering indexes and INCLUDE: stored values are not ordering keys.
-- These designs were discussed only; they were NOT created during the lesson.
-- Do not create every variation: overlapping indexes have maintenance costs.

/* Design alternatives only; choose according to a real workload:

-- Two search/order keys, plus id as payload for possible index-only access.
CREATE INDEX example_department_name_covering_idx
ON lab_index_employees (department_id, name) INCLUDE (id);

-- Three keys: additionally supplies id ordering within equal department/name.
CREATE INDEX example_department_name_id_idx
ON lab_index_employees (department_id, name, id);

-- Alternative key order for department filtering followed by id, name ordering.
CREATE INDEX example_department_id_name_idx
ON lab_index_employees (department_id, id, name);
*/

-- INCLUDE (id) carries id values but does not guide index searches or key ordering.
-- Covering makes index-only access possible, not mandatory or always heap-free.


-- 14. Core takeaways.
-- An index provides an access path; the optimizer decides whether to use it.
-- Reduce unnecessary data access, not the required result set.
-- Read candidate counts and filter counts at the node where they are reported.
-- Match composite key order to filtering and ordering requirements.
-- Key columns determine order; included columns carry additional values.
-- Only ORDER BY guarantees result order, regardless of available indexes.
-- Validate plans and buffer usage; never promise performance from one timing.

