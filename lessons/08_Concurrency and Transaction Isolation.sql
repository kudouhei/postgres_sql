-- Lesson 08: Concurrency, Isolation, MVCC, and Row Locks
-- Reference notes: do NOT execute this file as a single script.
-- Each experiment requires two independent sessions, A and B.
-- All experiment SQL is commented out. Copy statements individually into the
-- indicated session and execute in the numbered order, using the same connections.
-- In DBeaver, confirm Manual commit mode in BOTH editors before experimenting.
-- On macOS, select one complete statement and press Command+Enter.
-- Never repeat an UPDATE merely because its output was not copied.
--
-- Final committed state after the completed lesson:
--   lab_accounts: Alice (1) = 1250.00; Bob (2) = 600.00.
--   lab_doctors: Alice (1) = FALSE; Bob (2) = TRUE.
-- The successful isolation demonstrations committed account increases.
-- Locking experiments were rolled back and did not change that final balance.


-- 01. Identify independent sessions and their isolation levels.
-- pg_backend_pid() is a built-in function returning the server process ID
-- handling the current connection. It is not an employee ID or a DBeaver PID.
-- Observed IDs were A = 86556 and B = 87009; IDs can change after reconnecting.
-- Two editor tabs are not necessarily two independent database sessions.
-- current_setting(...) returns the current value of a PostgreSQL setting.

SELECT
    pg_backend_pid() AS session_id,
    current_setting('transaction_isolation') AS isolation_level;

-- Alternative: SHOW transaction_isolation;
-- Isolation level and Auto/Manual commit mode are different settings.


-- 02. Read Committed: a new snapshot for each ordinary SELECT.
-- A query sees data committed before it starts, plus its own transaction's changes.
-- It does not see another transaction's uncommitted changes: no dirty reads.
-- Two SELECTs in the SAME transaction may see different committed values.
-- That change to a previously read row is a non-repeatable read.
-- This replay commits a real +100 change; let S denote the starting balance.

/*
-- Step 1, B: start a fresh Read Committed transaction and read S.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT id, balance FROM lab_accounts WHERE id = 1;

-- Step 2, A: update, but do not commit yet.
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE lab_accounts
SET balance = balance + 100
WHERE id = 1
RETURNING id, balance;
-- A sees S + 100 in its own transaction.

-- Step 3, B: read again while A is still uncommitted.
SELECT id, balance FROM lab_accounts WHERE id = 1;
-- B still sees S. An ordinary SELECT does not wait for this UPDATE's row lock.

-- Step 4, A: commit the increase.
COMMIT;

-- Step 5, B: no reconnect or transaction restart between these reads.
SELECT id, balance FROM lab_accounts WHERE id = 1;
-- B now sees S + 100, even though B's transaction has not ended.
ROLLBACK;
-- Ends B's read-only transaction; it cannot undo A's committed change.
*/

-- Historical observation: B read 1050, then 1150 after A committed.
-- A result can change between statements without any dirty read occurring.


-- 03. Repeatable Read: a stable transaction snapshot for ordinary queries.
-- In PostgreSQL, the snapshot is established by the first non-transaction-control
-- statement, not necessarily by BEGIN itself. Own writes remain visible.
-- Later commits by other transactions do not replace this transaction's snapshot.
-- This replay also commits a real +100; S is its starting balance.

/*
-- Step 1, B: establish the snapshot by reading S.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT id, balance FROM lab_accounts WHERE id = 1;

-- Step 2, A: commit a new version.
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE lab_accounts
SET balance = balance + 100
WHERE id = 1
RETURNING id, balance;
COMMIT;

-- Step 3, B: keep the same transaction and connection.
SELECT id, balance FROM lab_accounts WHERE id = 1;
-- Still S, not S + 100.
ROLLBACK;

-- Step 4, B: a new transaction can read the new committed value.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT id, balance FROM lab_accounts WHERE id = 1;
-- Now S + 100.
ROLLBACK;
*/

-- Historical observation: B repeatedly read 1150, then read 1250 in a new transaction.


-- 04. MVCC: Multi-Version Concurrency Control.
-- PostgreSQL keeps row versions so an ordinary SELECT can read a visible version
-- while another transaction updates the row. Visibility is governed by snapshots.
-- This does NOT mean every SELECT is guaranteed never to wait: for example,
-- stronger table locks can block queries, and SELECT FOR UPDATE requests row locks.


-- 05. Concurrent UPDATEs of the same row can block one another.
-- The updater holds its row lock until its transaction ends.
-- SET LOCAL applies a setting only within the current transaction.
-- lock_timeout limits time spent waiting to acquire a lock, not total query runtime.

/*
-- Step 1, A: change Alice temporarily and keep the transaction open.
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE lab_accounts
SET balance = balance - 100
WHERE id = 1
RETURNING id, balance;

-- Step 2, B: attempt a competing update, with bounded waiting.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout = '5s';
UPDATE lab_accounts
SET balance = balance + 10
WHERE id = 1
RETURNING id, balance;
-- Expected after about 5 seconds: SQLSTATE 55P03, lock timeout.
-- Stop here; do not retry the UPDATE or commit.

-- Step 3, B: clean up the failed transaction.
ROLLBACK;

-- Step 4, A: discard the temporary debit and release its lock.
ROLLBACK;
*/

-- A lock timeout cancels B's waiting statement, not A's transaction.
-- Without client error recovery, B's transaction remains failed until rollback.
-- Neither the -100 nor the +10 was committed in this experiment.


-- 06. SELECT FOR UPDATE locks selected rows without changing their values.
-- Unlike an ordinary SELECT, it can wait for a conflicting row lock.

/*
-- Step 1, A: lock Alice without changing her balance.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT id, owner_name, balance
FROM lab_accounts
WHERE id = 1
FOR UPDATE;

-- Step 2, B: request a conflicting lock.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout = '5s';
SELECT id, owner_name, balance
FROM lab_accounts
WHERE id = 1
FOR UPDATE;
-- Expected: 55P03, canceling statement due to lock timeout.

-- Step 3, B:
ROLLBACK;
-- Step 4, A:
ROLLBACK;
*/


-- 07. A lock wait is not necessarily a deadlock.
-- Ordinary wait: B waits for A, while A is not waiting for B.
-- Deadlock: A holds Alice and waits for Bob, while B holds Bob and waits for Alice.
-- PostgreSQL detects deadlocks and aborts a transaction to break the cycle.
-- Acquire shared resources in a consistent order to reduce deadlock risk.
-- This prevents the illustrated reverse-order cycle, not every possible deadlock.
-- The lesson discussed deadlocks; it did not deliberately reproduce one.

/*
-- Use the same account-locking order in cooperating transactions.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT id, owner_name, balance
FROM lab_accounts
WHERE id IN (1, 2)
ORDER BY id
FOR UPDATE;
ROLLBACK;
*/


-- 08. Serializable and write skew.
-- Business rule: at least one doctor must remain on call.
-- With both doctors initially on call, each transaction could read a count of 2
-- and decide to take a DIFFERENT doctor off call. A stable snapshot alone does
-- not prevent both decisions from committing under Repeatable Read.
-- This write-skew result would leave zero doctors on call.
-- If executed serially with the check, the second transaction would see one doctor
-- remaining and would not take that doctor off call.
-- Serializable prevents committed results inconsistent with every serial ordering.
-- It does not literally run all transactions one at a time or infer business rules.

-- Existing experiment schema, for reference only; do not recreate the table.
/*
CREATE TABLE lab_doctors (
    id integer PRIMARY KEY,
    doctor_name text NOT NULL,
    on_call boolean NOT NULL
);
*/

-- Replay precondition: exactly Alice (1) and Bob (2), both TRUE and committed.
-- The lesson ended with Alice FALSE / Bob TRUE, so it is not currently at that
-- starting state. Reset only deliberately, before either experiment transaction:
/*
BEGIN;
UPDATE lab_doctors SET on_call = TRUE WHERE id IN (1, 2);
COMMIT;
*/

/*
-- Step 1, A: read the initial state and leave the transaction open.
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS on_call_count FROM lab_doctors WHERE on_call = TRUE;
-- Count: 2.

-- Step 2, B: read BEFORE A changes or commits anything.
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS on_call_count FROM lab_doctors WHERE on_call = TRUE;
-- Count: 2.

-- Step 3, A: based on its count, take Alice off call and commit.
UPDATE lab_doctors SET on_call = FALSE WHERE id = 1;
COMMIT;

-- Step 4, B: try to take Bob off call based on its earlier count.
UPDATE lab_doctors SET on_call = FALSE WHERE id = 2;
-- Observed: SQLSTATE 40001, read/write dependencies among transactions.
-- Serialization failure can occur during a statement or at COMMIT.
-- If UPDATE succeeds, attempt COMMIT; it must not be treated as proof of success.
-- After a serialization error, do NOT retry just the UPDATE.

-- Step 5, B: end the failed transaction, then restart the whole business operation.
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS on_call_count FROM lab_doctors WHERE on_call = TRUE;
-- Count: 1. Re-evaluate the rule: Bob must stay on call.
-- Do NOT execute the off-call UPDATE this time.
COMMIT;
*/

-- Final state: Alice FALSE, Bob TRUE. Application logic must implement the check.
-- Retry the entire transaction, including its reads and business decisions.
-- All relevant transactions must use the appropriate concurrency protocol;
-- one Serializable transaction does not make arbitrary concurrent writers safe.
-- Repeatable Read can also produce 40001, for example after a concurrent update;
-- 40001 does not by itself identify the transaction's isolation level.


-- 09. PostgreSQL isolation guarantees for changes made by OTHER transactions.
--                         Dirty read  Non-repeatable read  Phantom  Serialization anomaly
-- Read Committed          prevented   possible             possible possible
-- Repeatable Read         prevented   prevented            prevented possible
-- Serializable            prevented   prevented            prevented prevented
-- PostgreSQL Read Uncommitted behaves like Read Committed.
--
-- Non-repeatable read: a reread finds the same row's value changed.
-- Phantom read: a repeated condition query finds a changed set of matching rows.
-- Hypothetical example: WHERE on_call = TRUE first returns Bob; after another
-- transaction inserts and commits an on-call Carol, it returns Bob and Carol.
-- Read Committed permits this; PostgreSQL Repeatable Read keeps the original
-- snapshot and still returns only Bob. Carol was NOT inserted in this lesson.


-- 10. Client and cleanup reminders.
-- DBeaver's automatic recovery can roll back failed transactions on your behalf.
-- Distinguish PostgreSQL errors from any subsequent client rollback/retry behavior.
-- Never bypass an application decision by blindly retrying a failed write.
-- After an experiment, end transactions explicitly; idle transactions may retain
-- locks or old snapshots. ROLLBACK in B cannot undo a committed transaction in A.
-- Check the actual commit mode each time, especially after changing settings.
--
-- References:
-- https://www.postgresql.org/docs/18/transaction-iso.html
-- https://www.postgresql.org/docs/18/explicit-locking.html
-- https://dbeaver.com/docs/dbeaver/Separate-Connections/
-- https://github.com/dbeaver/dbeaver/issues/6479
