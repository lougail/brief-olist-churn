-- ============================================================
-- 01-schema.sql - Schéma DDL pour le dataset Olist
-- Crée les 8 tables avec types, contraintes PK/FK, et CHECK
-- ============================================================

-- Ordre de création : tables sans dépendances d'abord,
-- puis celles qui référencent les premières (intégrité FK).

-- ============================================================
-- Tables de référence (aucune dépendance)
-- ============================================================

CREATE TABLE customers (
    customer_id              VARCHAR(32) PRIMARY KEY,
    customer_unique_id       VARCHAR(32) NOT NULL,
    customer_zip_code_prefix VARCHAR(5)  NOT NULL,
    customer_city            VARCHAR(100) NOT NULL,
    customer_state           CHAR(2)     NOT NULL
);

CREATE TABLE sellers (
    seller_id              VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5)  NOT NULL,
    seller_city            VARCHAR(100) NOT NULL,
    seller_state           CHAR(2)     NOT NULL
);

CREATE TABLE products (
    product_id                 VARCHAR(32) PRIMARY KEY,
    product_category_name      VARCHAR(100),
    product_name_lenght        SMALLINT,
    product_description_lenght SMALLINT,
    product_photos_qty         SMALLINT,
    product_weight_g           INTEGER,
    product_length_cm          SMALLINT,
    product_height_cm          SMALLINT,
    product_width_cm           SMALLINT
);

CREATE TABLE product_category_translation (
    product_category_name         VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100) NOT NULL
);

-- ============================================================
-- Table centrale : orders (dépend de customers)
-- ============================================================

CREATE TABLE orders (
    order_id                      VARCHAR(32) PRIMARY KEY,
    customer_id                   VARCHAR(32) NOT NULL REFERENCES customers(customer_id),
    order_status                  VARCHAR(20) NOT NULL,
    order_purchase_timestamp      TIMESTAMP   NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP   NOT NULL
);

-- ============================================================
-- Tables dépendantes de orders
-- ============================================================

CREATE TABLE order_items (
    order_id            VARCHAR(32) NOT NULL REFERENCES orders(order_id),
    order_item_id       INTEGER     NOT NULL,
    product_id          VARCHAR(32) NOT NULL REFERENCES products(product_id),
    seller_id           VARCHAR(32) NOT NULL REFERENCES sellers(seller_id),
    shipping_limit_date TIMESTAMP   NOT NULL,
    price               NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freight_value       NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id             VARCHAR(32)   NOT NULL REFERENCES orders(order_id),
    payment_sequential   INTEGER       NOT NULL,
    payment_type         VARCHAR(20)   NOT NULL,
    payment_installments INTEGER       NOT NULL,
    payment_value        NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE order_reviews (
    review_id              VARCHAR(32) PRIMARY KEY,
    order_id               VARCHAR(32) NOT NULL REFERENCES orders(order_id),
    review_score           SMALLINT    NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title   TEXT,
    review_comment_message TEXT,
    review_creation_date   TIMESTAMP   NOT NULL,
    review_answer_timestamp TIMESTAMP  NOT NULL
);
