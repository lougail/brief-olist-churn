-- ============================================================
-- 03-nettoyage.sql - Identification et correction des anomalies
-- Chaque anomalie est documentée : constat, décision, requête.
-- ============================================================

-- ============================================================
-- ANOMALIE 1 : Doublons dans order_reviews
-- Constat  : 949 review_id apparaissent plus d'une fois dans le CSV.
-- Décision : Dédupliqué à l'import (02-import.sql) avec DISTINCT ON.
--            On garde la review la plus RÉCENTE par review_creation_date
--            (= dernière version du jugement client).
-- Action   : Aucune ici, déjà traité. Vérification :
-- ============================================================

SELECT 'reviews_doublons_restants' AS check_name,
       COUNT(*) - COUNT(DISTINCT review_id) AS duplicates
FROM order_reviews;

-- ============================================================
-- ANOMALIE 2 : 8 commandes "delivered" sans date de livraison client
-- Constat  : order_status = 'delivered' mais order_delivered_customer_date IS NULL.
--            6 sur 8 ont une date carrier, 1 n'a aucune date.
-- Décision : Estimer la date de livraison client.
--            - Si carrier_date existe : customer_date = carrier_date + 7 jours
--              (délai moyen transporteur → client observé dans le dataset)
--            - Si carrier_date manque aussi : customer_date = purchase + 14 jours
-- Justif.  : Le statut "delivered" confirme la livraison ; la date manque
--            par erreur de tracking, pas parce qu'elle n'a pas eu lieu.
-- ============================================================

UPDATE orders
SET order_delivered_customer_date = COALESCE(
    order_delivered_carrier_date + INTERVAL '7 days',
    order_purchase_timestamp + INTERVAL '14 days'
)
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- Vérification : plus aucune commande delivered sans date
SELECT 'delivered_sans_date' AS check_name,
       COUNT(*) AS remaining
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- ============================================================
-- ANOMALIE 3 : 610 produits sans catégorie (product_category_name IS NULL)
-- Constat  : 1.9% des produits n'ont pas de catégorie assignée.
-- Décision : Remplacer NULL par 'sem_categoria' pour qu'ils soient
--            comptés dans les agrégations (COUNT DISTINCT ignore les NULL).
-- ============================================================

UPDATE products
SET product_category_name = 'sem_categoria'
WHERE product_category_name IS NULL;

-- Vérification
SELECT 'produits_sans_categorie' AS check_name,
       COUNT(*) AS remaining
FROM products
WHERE product_category_name IS NULL;

-- ============================================================
-- ANOMALIE 4 : 2 catégories sans traduction anglaise
-- Constat  : 'portateis_cozinha_e_preparadores_de_alimentos' (10 produits)
--            et 'pc_gamer' (3 produits) n'ont pas d'entrée dans la table
--            product_category_translation.
-- Décision : Ajouter les traductions manuellement.
--            On en profite pour ajouter 'sem_categoria' (créée à l'anomalie 3)
--            afin qu'elle ait aussi sa traduction anglaise.
-- ============================================================

INSERT INTO product_category_translation VALUES
    ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_processors'),
    ('pc_gamer', 'pc_gamer'),
    ('sem_categoria', 'no_category')
ON CONFLICT (product_category_name) DO NOTHING;

-- Vérification : toutes les catégories produits ont une traduction
SELECT 'categories_sans_traduction' AS check_name,
       COUNT(DISTINCT p.product_category_name) AS missing
FROM products p
LEFT JOIN product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL;

-- ============================================================
-- ANOMALIE 5 (observée, non corrigée) : 9 paiements à 0€
-- Constat  : 6 sont des vouchers (bons de réduction épuisés = normal),
--            3 sont 'not_defined' sur des commandes annulées.
-- Décision : Laisser en l'état - pas d'impact sur les features car
--            les montants sont agrégés par commande et ces valeurs
--            n'altèrent pas les totaux.
-- ============================================================

-- Résumé final du nettoyage
SELECT 'total_customers' AS metric, COUNT(*)::TEXT AS value FROM customers
UNION ALL SELECT 'total_orders', COUNT(*)::TEXT FROM orders
UNION ALL SELECT 'total_order_items', COUNT(*)::TEXT FROM order_items
UNION ALL SELECT 'total_reviews', COUNT(*)::TEXT FROM order_reviews
UNION ALL SELECT 'total_products', COUNT(*)::TEXT FROM products
UNION ALL SELECT 'delivered_orders', COUNT(*)::TEXT FROM orders WHERE order_status = 'delivered'
ORDER BY metric;
