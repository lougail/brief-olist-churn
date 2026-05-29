-- ============================================================
-- 02-import.sql - Import des CSV dans PostgreSQL
-- Ordre : tables de référence d'abord (FK), puis dépendantes.
-- Les fichiers CSV sont montés dans /data/ via docker-compose.
-- ============================================================

-- Tables de référence (aucune FK entrante requise)
COPY customers FROM '/data/olist_customers_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

COPY sellers FROM '/data/olist_sellers_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

COPY products FROM '/data/olist_products_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

-- Nettoyage du BOM UTF-8 sur le fichier category_translation
-- On crée une table temporaire en TEXT, on nettoie, puis on insère
CREATE TEMP TABLE tmp_cat_translation (
    product_category_name         TEXT,
    product_category_name_english TEXT
);

COPY tmp_cat_translation FROM '/data/product_category_name_translation.csv'
    WITH (FORMAT csv, HEADER true);

INSERT INTO product_category_translation
SELECT REPLACE(product_category_name, E'﻿', ''),
       product_category_name_english
FROM tmp_cat_translation;

DROP TABLE tmp_cat_translation;

-- Table centrale
COPY orders FROM '/data/olist_orders_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

-- Tables dépendantes de orders
COPY order_items FROM '/data/olist_order_items_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

COPY order_payments FROM '/data/olist_order_payments_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

-- Reviews : dédupliquer les review_id en doublon (949 doublons dans le CSV)
-- On garde la review la plus RÉCENTE (DESC) : c'est la dernière version du jugement client.
CREATE TEMP TABLE tmp_reviews (
    review_id              VARCHAR(32),
    order_id               VARCHAR(32),
    review_score           SMALLINT,
    review_comment_title   TEXT,
    review_comment_message TEXT,
    review_creation_date   TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

COPY tmp_reviews FROM '/data/olist_order_reviews_dataset.csv'
    WITH (FORMAT csv, HEADER true, QUOTE '"');

INSERT INTO order_reviews
SELECT DISTINCT ON (review_id) *
FROM tmp_reviews
ORDER BY review_id, review_creation_date DESC;

DROP TABLE tmp_reviews;

-- ============================================================
-- Vérification post-import : nombre de lignes par table
-- ============================================================
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'product_category_translation', COUNT(*) FROM product_category_translation
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
ORDER BY table_name;
