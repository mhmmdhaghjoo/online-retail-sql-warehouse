-- 01_staging.sql
-- Land the raw CSV exports unchanged. Staging tables carry no constraints:
-- the point is to get everything in, then measure what is wrong with it.

DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA staging;

CREATE TABLE staging.customers (
    customer_id         integer,
    signup_date         date,
    country             text,
    acquisition_channel text,
    birth_year          integer
);

CREATE TABLE staging.products (
    product_id   text,
    product_name text,
    category     text,
    unit_price   numeric(10, 2),
    unit_cost    numeric(10, 2)
);

CREATE TABLE staging.order_lines (
    order_id     text,
    order_ts     timestamp,
    customer_id  integer,
    product_id   text,
    quantity     integer,
    unit_price   numeric(10, 2),
    discount_pct numeric(4, 2)
);

-- \copy runs on the client, so no server-side file permissions are needed.
\copy staging.customers   FROM 'data/raw/customers.csv'   WITH (FORMAT csv, HEADER true)
\copy staging.products    FROM 'data/raw/products.csv'    WITH (FORMAT csv, HEADER true)
\copy staging.order_lines FROM 'data/raw/order_lines.csv' WITH (FORMAT csv, HEADER true)
