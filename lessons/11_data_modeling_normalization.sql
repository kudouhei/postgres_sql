-- Lesson 11: Data Modeling and Normalization
-- English reference notes. Execute one complete statement at a time.
-- Executable SQL below is read-only. VALUES supplies query-local sample data.
-- All CREATE / INSERT / transaction-control examples are commented out.
-- lab_employee_phones was already created during this lesson: do NOT recreate it
-- or repeat its inserts unless deliberately rebuilding the experiment.
-- Legal, the department rename, Carol's deletion, courses, and orders were
-- hypothetical examples; they did not change the existing database.


-- 01. Keep independently maintained facts in appropriate tables.
-- Imagine storing the department name in every employee record:

SELECT *
FROM (
    VALUES
        (101, 'Alice', 1, 'Engineering'),
        (102, 'Bob',   1, 'Engineering'),
        (103, 'Carol', 2, 'Finance')
) AS sample(employee_id, employee_name, department_id, department_name)
ORDER BY employee_id;

-- Update anomaly: rename Engineering in Alice's row but not Bob's row.
-- The same department then has inconsistent names; filtering by the new name
-- misses Bob. This is a maintenance problem, not merely wasted storage.
-- Deletion anomaly: deleting Finance's last employee also loses the only stored
-- evidence that Finance exists, even if the department has not been dissolved.
-- Insertion anomaly: if every row requires a non-NULL employee ID, a new Legal
-- department with no employees cannot be recorded without inventing an employee.
-- Separate departments from employees so each can be maintained independently.


-- 02. Functional dependency: A -> B means that A determines B.
-- In any valid database state, equal A values must imply equal B values.
-- This is a rule about the data, NOT SQL syntax or a SQL function.
-- It means one determined value, not an arbitrary list of matching values.
-- It does NOT imply B -> A, and does not mean values can never change over time.
-- Determine dependencies from business rules, not accidental uniqueness in a sample.
--
-- employee_id   -> employee_name: yes, the employee ID identifies the employee.
-- department_id -> department_name: yes, one department has one current name.
-- department_id -> employee_name: no, department 1 contains both Alice and Bob.
-- employee_name -> employee_id: no, different employees may both be named Alex.

SELECT id, name
FROM employees
WHERE id = 101;

-- Employee 101 is Alice; no telephone number is needed to determine the name.
-- A superkey determines all attributes of a relation.
-- A candidate key is a minimal superkey: removing any member breaks that property.
-- The primary key is the candidate key selected as the main identifier.
-- A prime attribute belongs to at least one candidate key; a non-prime one does not.


-- 03. First Normal Form (1NF): single domain values, without repeating groups.
-- In this exercise each phone number needs independent querying and maintenance.
-- Packing multiple numbers into one comma-separated string hides that structure.
-- Atomicity depends on the intended domain; normalization is not a rule to split
-- every string into smaller pieces regardless of its meaning.

SELECT employee_id, employee_name, phones
FROM (
    VALUES
        (101, 'Alice', '13800000001,13900000002'),
        (102, 'Bob',   '13700000003')
) AS sample(employee_id, employee_name, phones)
WHERE phones = '13900000002';

-- Expected: ZERO ROWS, not a row containing NULL.
-- Equality compares the entire stored string, not one member of the list.
-- Zero rows means no matching record; NULL means a missing/unknown field value.

SELECT employee_id, phone
FROM (
    VALUES
        (101, '13800000001'),
        (101, '13900000002'),
        (102, '13700000003')
) AS sample(employee_id, phone)
WHERE phone = '13900000002';

-- Expected: (101, '13900000002'). One phone number is stored per record.
-- Phone numbers are text identifiers, not numbers to use in arithmetic.


-- 04. Composite primary key: the complete combination must be unique.
-- employee_id alone cannot identify a phone record: an employee may have many.
-- Our rule: the same employee/phone pair is recorded once; different employees
-- may share a phone number. Phone is NOT globally unique in this model.
-- A column can be both a foreign key and part of a composite primary key.

/* Already performed: schema reference only.
CREATE TABLE lab_employee_phones (
    employee_id integer NOT NULL REFERENCES employees(id),
    phone text NOT NULL,
    PRIMARY KEY (employee_id, phone)
);

INSERT INTO lab_employee_phones (employee_id, phone)
VALUES
    (101, '13800000001'),
    (101, '13900000002')
RETURNING employee_id, phone;

-- Save the successful baseline before an intentional failure in Manual mode.
COMMIT;
*/

/* Intentional failure already tested; do not run as part of a script.
INSERT INTO lab_employee_phones (employee_id, phone)
VALUES (101, '13900000002');

-- Expected SQLSTATE 23505: duplicate combination violates
-- lab_employee_phones_pkey. The rejected insert adds no row.
-- A failed transaction may require ROLLBACK before further commands.
ROLLBACK;
-- This cannot undo records committed in the earlier transaction.
*/

/* Sharing a phone number succeeded in the lesson; do not repeat the insert.
INSERT INTO lab_employee_phones (employee_id, phone)
VALUES (102, '13900000002')
RETURNING employee_id, phone;

-- If using Manual commit mode, commit the intended successful change.
COMMIT;
*/

SELECT employee_id, phone
FROM lab_employee_phones
ORDER BY employee_id, phone;

-- Observed final rows:
-- 101 | 13800000001
-- 101 | 13900000002
-- 102 | 13900000002
-- Both individual columns repeat; the complete pairs remain unique.
-- A primary key rejects NULL key values; a foreign key validates employee IDs.


-- 05. Second Normal Form (2NF): 1NF plus no partial dependency of a non-prime
-- attribute on ANY candidate key. Each such attribute must depend on the whole key.
-- Our examples use the chosen composite primary key to illustrate the rule.
-- Imagine lab_employee_phones also stored employee_name:
--   key: (employee_id, phone)
--   employee_id -> employee_name
-- The name depends on only part of the key: a partial dependency.
-- Keep employee_name in employees, not duplicated for each phone number.

SELECT
    p.employee_id,
    e.name AS employee_name,
    p.phone
FROM lab_employee_phones AS p
JOIN employees AS e
    ON e.id = p.employee_id
ORDER BY p.employee_id, p.phone;

-- Expected: Alice beside each of her two numbers, Bob beside his shared number.
-- The JOIN displays Alice twice but her name is stored once in employees.
-- Repetition in a query result is not the same as redundant stored facts.


-- 06. Full versus partial dependency: the course example.
-- Assumptions: one score per employee/course pair; different employees can have
-- different scores for the same course, and an employee can take many courses.
--
-- employee_courses(employee_id, course_id, score)
--   key: (employee_id, course_id)
--   (employee_id, course_id) -> score: both are needed.
--
-- Employee 101: SQL = 90, Python = 80. Employee ID alone does not determine score.
-- Course ID alone does not determine all employees' individual scores either.
-- Adding course_name would introduce course_id -> course_name: partial dependency.
--
-- Suitable separation (design only; no course tables were created):
--   employees(id, name, ...)
--   courses(course_id, course_name)
--   employee_courses(employee_id, course_id, score)
-- Course details belong to courses; the employee's result belongs to the pairing.


-- 07. Third Normal Form (3NF): address inappropriate transitive dependencies.
-- In the mixed employee/department design from section 01:
--   employee_id -> department_id -> department_name
-- department_id is not an employee key: several employees share a department.
-- department_name is non-prime in that mixed relation and depends on this non-key
-- determinant. Store the department's name independently instead.
--
-- Existing separation:
--   employees(id, name, department_id, salary)
--   departments(id, name)
--   employees.department_id REFERENCES departments(id)

SELECT
    e.id AS employee_id,
    e.name AS employee_name,
    d.id AS department_id,
    d.name AS department_name
FROM employees AS e
JOIN departments AS d
    ON d.id = e.department_id
ORDER BY e.id;

-- Renaming a department requires updating one department row, not every employee.
-- Deleting an employee does not by itself delete that employee's department.
-- A department can exist before its first employee.
-- Stable IDs keep relationships independent of mutable names.
-- Foreign keys need not reference columns named id: eligible unique keys also work.

-- Precision note: 3NF is not a ban on EVERY possible transitive dependency.
-- Formally, for every non-trivial FD X -> A, either X is a superkey or A is prime.
-- Non-trivial means A is not already a member of X.
-- The examples here have straightforward keys and non-prime descriptive fields.
-- Normal forms consider all candidate keys, not just the declared primary key.
-- Choosing a single-column primary key alone does not eliminate redundancy.


-- 08. Not every repeated value is redundant information.
-- employee_id repeats in the phone table because one employee has multiple phones.
-- department_id repeats in employees because multiple employees share a department.
-- These rows record different relationships, not multiple editable department names.
-- Normalization does not mean removing all duplicate values or avoiding JOINs.


-- 09. Historical facts must not be replaced by current facts.
-- products.current_price: what the product costs now.
-- order_items.unit_price: what a particular order item actually sold for.
-- If yesterday's sale was 80 and today's price becomes 120, keep the sale at 80.
-- Even if both prices initially match, they represent different facts.
-- Joining to the current product price cannot reconstruct the original sale price.
-- This is not redundant storage of the same fact simply because both are prices.
-- These were conceptual examples only; no products/orders tables were created.


-- 10. Core checklist.
-- Identify the entity or relationship each fact describes.
-- Identify candidate keys and dependencies from business rules.
-- 1NF: use appropriately atomic values; avoid independently managed repeating lists.
-- 2NF: avoid non-prime attributes depending on only part of a candidate key.
-- 3NF: remove violations such as department facts embedded in employee records.
-- Preserve relationships with keys; recover useful combined views with JOINs.
-- Keep historical facts where the relevant transaction can retain them.
-- Normalize according to meaning, not by mechanically maximizing the table count.

-- References:
-- https://www.postgresql.org/docs/18/ddl-constraints.html
-- https://cs186berkeley.net/sp22/resources/static/notes/n16-DBDesign.pdf
-- https://cs.rpi.edu/~sibel/csci4380/fall2026/course_notes/normalization.html
-- https://learn.microsoft.com/en-us/previous-versions/troubleshoot/microsoft-365/microsoft-365-apps/access/database-normalization-description
