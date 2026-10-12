-- Lesson 1: Tables and constraints

CREATE TABLE departments (
    id integer PRIMARY KEY,
    name text NOT NULL UNIQUE,

    CONSTRAINT departments_name_not_blank
        CHECK (length(btrim(name)) > 0)
);

INSERT INTO departments (id, name)
VALUES
    (1, 'Engineering'),
    (2, 'Finance'),
    (3, 'Human Resources');

SELECT id, name
FROM departments
ORDER BY id;