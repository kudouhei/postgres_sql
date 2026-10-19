-- Lesson 07: Transactions and Savepoints
-- Reference notes, not a setup/reset script.
-- Data-changing examples are inside block comments to prevent accidental execution.
-- To practise, copy one example body into the SQL editor and execute statements
-- individually in the same connection. Do not run every example as one script.
-- The only executable statement outside comments is the final read-only SELECT.
--
-- Current committed baseline after the lesson:
--   Alice (id 1): 950.00; Bob (id 2): 600.00.
-- Historical setup was 1000 / 500; the committed transfer produced 900 / 600.
-- A later +50 ran in Auto-commit mode, changing the baseline to 950 / 600.
-- The savepoint experiment was fully rolled back to that latest baseline.


-- 01. Experiment table: existing schema, shown for reference only.
-- NOT NULL rejects missing balances; CHECK rejects negative balances.
-- Do not recreate the table or reinsert its existing accounts.

/*
CREATE TABLE lab_accounts (
    id integer PRIMARY KEY,
    owner_name text NOT NULL,
    balance numeric(12, 2) NOT NULL,
    CONSTRAINT lab_accounts_balance_non_negative
        CHECK (balance >= 0)
);
*/


-- 02. A transaction groups operations into an all-or-nothing unit.
-- BEGIN starts a transaction. COMMIT commits its remaining changes.
-- ROLLBACK discards all uncommitted changes in the transaction.
-- Returning or selecting a changed value does NOT prove it has been committed.
-- A transaction can read its own uncommitted changes.
-- This example changes Alice's balance temporarily, then restores it.

/*
BEGIN;

UPDATE lab_accounts
SET balance = balance - 100
WHERE id = 1
RETURNING id, owner_name, balance;
-- Starting from 950, this shows 850; the change is still uncommitted.

ROLLBACK;

SELECT id, owner_name, balance
FROM lab_accounts
ORDER BY id;
-- Back to Alice 950 / Bob 600.
*/


-- 03. Commit multiple updates together.
-- This is a transaction-control example, not a complete production transfer.
-- Both updates must affect exactly one intended account; the application must
-- check this before COMMIT. Zero affected rows do not cause an SQL error.
-- A real transfer also requires appropriate validation and concurrency handling.
-- WARNING: running this example commits a new balance baseline.

/*
BEGIN;

UPDATE lab_accounts
SET balance = balance - 100
WHERE id = 1
RETURNING id, owner_name, balance;

UPDATE lab_accounts
SET balance = balance + 100
WHERE id = 2
RETURNING id, owner_name, balance;

-- Check that each UPDATE returned exactly one row before proceeding.
COMMIT;
*/

-- COMMIT does not apply the updates a second time; it commits existing changes.
-- A later ROLLBACK cannot undo a transaction that has already committed.
-- New transactions can still modify the balances; that is not undoing the old commit.


-- 04. Statement errors can leave a transaction in a failed state.
-- Without savepoint recovery or client cleanup, a statement error inside the
-- transaction prevents ordinary statements from continuing until rollback.
-- SQLSTATE 23514: CHECK constraint violation.
-- SQLSTATE 25P02: current transaction is already in a failed state.
-- Execute each statement separately; the UPDATE and SELECT intentionally fail.
-- DBeaver auto-recovery can hide 25P02 by rolling back and retrying the query.

WHERE id = 1;

UPDATE lab_accounts
SET balance = -1
WHERE id = 2;
-- Expected: 23514. The negative balance is rejected.

SELECT 'after_error' AS check_step, id, owner_name, balance
FROM lab_accounts
ORDER BY id;
-- Expected without automatic recovery: 25P02, not a new balance result.

ROLLBACK;
-- Discards the earlier successful debit too, not just the invalid update.
*/


-- 05. Zero affected rows are not an SQL error.
-- Account 999 does not exist in this lab, so RETURNING produces no rows.
-- The transaction is not aborted merely because no row matched the WHERE clause.
-- If a debit succeeds but the matching credit affects zero rows, COMMIT can
-- still commit the debit. Check affected row counts and roll back explicitly.
-- Atomicity does not guarantee business correctness.

/*
BEGIN;

UPDATE lab_accounts
SET balance = balance + 100
WHERE id = 999
RETURNING id, owner_name, balance;

ROLLBACK;
*/


-- 06. SAVEPOINT marks a rollback position; it does not commit changes.
-- SAVEPOINT requires an active transaction block; it does not start one.
-- SQLSTATE 25P01: SAVEPOINT was attempted outside a transaction block.
-- ROLLBACK TO undoes changes after the savepoint while keeping earlier changes
-- uncommitted and leaving the transaction open.
-- Starting baseline for this independent example: Alice 950 / Bob 600.

/*
BEGIN;

UPDATE lab_accounts
SET balance = balance + 50
WHERE id = 1
RETURNING balance;
-- Alice: 1000, uncommitted.

SAVEPOINT after_first_change;

UPDATE lab_accounts
SET balance = balance + 20
WHERE id = 1
RETURNING balance;
-- Alice: 1020, uncommitted.

ROLLBACK TRANSACTION TO after_first_change;
-- Equivalent PostgreSQL syntax: ROLLBACK TO SAVEPOINT after_first_change;
-- The TRANSACTION form worked around the DBeaver issue observed in this lesson.

SELECT id, owner_name, balance
FROM lab_accounts
ORDER BY id;
-- Alice: 1000 / Bob: 600. The +20 is undone; the earlier +50 remains uncommitted.

ROLLBACK;
-- Full rollback: Alice returns to 950; Bob remains 600.
*/

-- If COMMIT replaced the final full ROLLBACK, Alice would be saved at 1000,
-- NOT 1020: COMMIT does not reapply the +20 that was already rolled back.
-- That COMMIT was hypothetical; it was not performed in the completed experiment.


-- 07. DBeaver observations: client behavior is separate from PostgreSQL semantics.
-- Auto-commit: standalone updates are committed automatically unless an explicit
-- transaction block is active. Do not infer mode from a previous experiment.
-- Manual commit: changes remain pending until the transaction is committed/rolled back.
-- Toolbar Auto indicates auto-commit; a pending modification count indicates
-- uncommitted work. None means no pending modifications, not proof of no transaction.
-- On macOS, select ONE complete statement and press Command+Enter.
-- Statement execution and script execution can have different transaction handling.
--
-- Connection auto-recover enabled can automatically recover an aborted PostgreSQL
-- transaction by rolling it back. This explained the initially missing 25P02 error.
-- We temporarily disabled it only for interview_lab, with Rollback on error off,
-- reproduced 25P02, then restored the connection's original global inheritance.
--
-- In the savepoint experiment, ROLLBACK TO SAVEPOINT unexpectedly returned Alice
-- to 950 rather than 1000. DBeaver has a matching reported issue in manual mode.
-- Repeating the experiment with ROLLBACK TRANSACTION TO after_first_change
-- correctly returned 1000. This is a client workaround, not different SQL semantics.
-- Do not substitute the toolbar Rollback button for ROLLBACK TO: it rolls back
-- the whole transaction.
--
-- References:
-- https://www.postgresql.org/docs/18/sql-savepoint.html
-- https://www.postgresql.org/docs/18/sql-rollback-to.html
-- https://dbeaver.com/docs/dbeaver/Auto-and-Manual-Commit-Modes/
-- https://github.com/dbeaver/dbeaver/issues/6479
-- https://github.com/dbeaver/dbeaver/issues/35821


-- Read-only check of current balances; this does not reset any data.
SELECT id, owner_name, balance
FROM lab_accounts
ORDER BY id;