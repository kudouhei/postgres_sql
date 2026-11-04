-- Lesson 12: UPSERT and Conflict Handling (PostgreSQL 18)
-- English reference notes. Do NOT execute this file as one practice script.
-- All write examples are commented out; executable queries are read-only.
-- Copy a write statement only when intentionally repeating that experiment.
-- Expected outcomes describe the state WHEN each experiment was performed.
-- Replaying writes now can change the final labels or produce different results.
-- The race-condition and foreign-key-error examples were discussed, not executed.


-- 01. Existing lab table and the label column.
-- Created in Lesson 11: lab_employee_phones(employee_id, phone).
-- Composite primary key: (employee_id, phone).
-- Foreign key: employee_id REFERENCES employees(id).
-- Different employees may share a number; one complete pair cannot repeat.

/* Already performed in Lesson 12; do not add the column again.
ALTER TABLE lab_employee_phones
ADD COLUMN label text NOT NULL DEFAULT 'personal';

-- In Manual commit mode, save intentional successful changes.
COMMIT;
*/

-- Existing records received the personal default. Inserts omitting label use it too.
-- An explicit NULL is not replaced by the default; label is NOT NULL.


-- 02. The conflict target identifies the unique key used to handle a conflict.
-- ON CONFLICT (employee_id, phone) matches our composite primary key.
-- Both values must match an existing pair; one matching column is not sufficient.
-- The target must have suitable unique enforcement; it is not an arbitrary filter.
-- employee_id alone is not unique in this table.


-- 03. DO NOTHING: skip a conflicting insert; otherwise insert normally.

/* Observed: existing Alice pair -> zero RETURNING rows; existing row unchanged.
INSERT INTO lab_employee_phones (employee_id, phone)
VALUES (101, '13900000002')
ON CONFLICT (employee_id, phone) DO NOTHING
RETURNING employee_id, phone;
*/

/* Observed on first execution: Carol's pair was new -> one inserted row.
INSERT INTO lab_employee_phones (employee_id, phone)
VALUES (103, '13700000003')
ON CONFLICT (employee_id, phone) DO NOTHING
RETURNING employee_id, phone;

-- This pair exists now: repeating this statement would skip it instead.
*/

-- DO NOTHING does not delete or update the existing record.
-- Zero returned rows is not a returned row containing NULL.


-- 04. DO UPDATE: insert a missing row, or update the conflicting row (UPSERT).
-- EXCLUDED refers to the proposed incoming row, not the existing stored row.
-- For the statement below, EXCLUDED.label is the incoming value 'work'.

/* Bob's existing pair was updated to work; Alice's records were not affected.
INSERT INTO lab_employee_phones (employee_id, phone, label)
VALUES (102, '13900000002', 'work')
ON CONFLICT (employee_id, phone)
DO UPDATE
SET label = EXCLUDED.label
RETURNING employee_id, phone, label;
*/

-- VALUES supplies the proposal; ON CONFLICT identifies the key; DO UPDATE selects
-- the action; SET chooses updated fields; RETURNING reports the resulting rows.
-- Changing the VALUES label to home makes EXCLUDED.label home automatically.
-- SET label = 'work' is valid but hard-codes work regardless of the incoming label.
-- String literals use single quotes, not backticks. SQL lines need no trailing \.
-- Alice's (101, '13900000002') was similarly updated to work in the earlier exercise.


-- 05. Update only when the label actually differs.
-- lab_employee_phones.label reads the existing label; EXCLUDED.label reads the
-- proposed label. Both are non-NULL here, so <> works for the comparison.

/* At this stage Bob's label was work. Incoming work -> no update, zero rows.
INSERT INTO lab_employee_phones (employee_id, phone, label)
VALUES (102, '13900000002', 'work')
ON CONFLICT (employee_id, phone)
DO UPDATE
SET label = EXCLUDED.label
WHERE lab_employee_phones.label <> EXCLUDED.label
RETURNING employee_id, phone, label;

-- Bob's final label is home now, so replaying this would change it back to work.
*/

/* Next experiment: existing work, incoming home -> update and return one row.
INSERT INTO lab_employee_phones (employee_id, phone, label)
VALUES (102, '13900000002', 'home')
ON CONFLICT (employee_id, phone)
DO UPDATE
SET label = EXCLUDED.label
WHERE lab_employee_phones.label <> EXCLUDED.label
RETURNING employee_id, phone, label;
*/

-- This WHERE controls the conflict UPDATE, not the insertion of a missing key.
-- Without this condition, equal incoming values do not automatically skip UPDATE.
-- Ordinary <> can yield UNKNOWN with NULL inputs; nullable fields need a NULL-aware
-- policy, commonly IS DISTINCT FROM when comparing old and new values.
-- A skipped conflict UPDATE can still lock the existing row; no update does not
-- mean no lock. End transactions promptly after the intended work.


-- 06. RETURNING reports rows actually inserted or updated.
-- Successful new insert: one row in our single-row examples.
-- Successful conflict UPDATE: one row, with its resulting values.
-- DO NOTHING on a duplicate: zero rows.
-- Conflict UPDATE whose WHERE is false: zero rows.
-- Zero rows does not imply the stored record is missing or deleted.
-- A returned row alone does not tell whether it was inserted or updated.

SELECT employee_id, phone, label
FROM lab_employee_phones
WHERE employee_id = 102
  AND phone = '13900000002';

-- Observed final value: (102, '13900000002', 'home').


-- 07. Why SELECT-then-INSERT can race.
-- A checks a new key: absent. B checks it too: absent.
-- A inserts and commits. B then performs a plain INSERT using its earlier result.
-- B encounters a duplicate key; its earlier SELECT did not reserve the key.
-- The unique constraint protects the data, but the application must handle the race.
-- UPSERT handles the insert-or-conflict action within one database statement.
-- Atomic conflict handling is not a guarantee that all business rules are satisfied.


-- 08. Atomic does not mean wait-free.
-- Conceptual scenarios: assume Read Committed, no other writers, no timeout/error,
-- and B attempts the same new unique pair while A's insert is still uncommitted.
-- B may need to wait for A's transaction to finish.
--
-- If A COMMITs:
--   B with DO NOTHING skips the conflicting insert.
--   B with unconditional DO UPDATE updates the now-existing conflicting row.
-- If A ROLLBACKs:
--   A's row disappears; B can insert B's proposed row instead.
-- A's rollback does not automatically roll back B's transaction.
--
-- Example: A proposes home, B proposes work and uses SET label = EXCLUDED.label.
-- A commits, then B's conflict UPDATE succeeds -> resulting label is work.
-- EXCLUDED in B belongs to B's statement, not A's input.
-- These scenarios do not promise automatic success at every isolation level:
-- serialization failures, deadlocks, and other errors still require handling.


-- 09. ON CONFLICT does not bypass other constraints.
-- Uniqueness question: does the employee/phone pair already exist?
-- Foreign-key question: does the referenced employee exist?
-- These are different checks; a new pair may still reference a nonexistent employee.

/* Hypothetical error example ONLY; this was not executed during the lesson.
-- Assumes employee 999 does not exist and this pair is new.
INSERT INTO lab_employee_phones (employee_id, phone, label)
VALUES (999, '13500000004', 'work')
ON CONFLICT (employee_id, phone) DO NOTHING;

-- Expected: foreign-key violation (23503), NOT a silently skipped insert.
-- NOT NULL and CHECK violations are not generally suppressed either.
-- If an error aborts a transaction, recover with ROLLBACK as in Lesson 07.
*/


-- 10. Choose the conflict policy from the business requirement.
-- Preserve the existing record when the key repeats: DO NOTHING.
-- Accept specified incoming fields for the existing key: DO UPDATE ... EXCLUDED.
-- Examples: user settings, externally keyed record sync, recalculated summaries.
-- Unconditional overwrite does not prove the incoming business data is newer.
-- Historical sale prices should not be overwritten merely because a key repeats.
-- UPSERT is not a complete exactly-once business-processing mechanism by itself.


-- 11. Final observed state after Lesson 12.
-- In Manual commit mode, successful changes require COMMIT to persist.
-- This SELECT alone does not prove whether the current transaction is committed.

SELECT employee_id, phone, label
FROM lab_employee_phones
ORDER BY employee_id, phone;

-- employee_id | phone       | label
-- 101         | 13800000001 | personal
-- 101         | 13900000002 | work
-- 102         | 13900000002 | home
-- 103         | 13700000003 | personal

-- Core terms: conflict target, composite key, proposed row, existing row,
-- UPSERT, conditional update, RETURNING, race condition, and lock waiting.

-- PostgreSQL 18 reference documentation:
-- https://www.postgresql.org/docs/18/sql-insert.html
-- https://www.postgresql.org/docs/18/transaction-iso.html
-- https://www.postgresql.org/docs/18/functions-comparison.html
-- https://www.postgresql.org/docs/18/ddl-constraints.html
