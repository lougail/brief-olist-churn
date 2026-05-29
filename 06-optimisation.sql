-- ============================================================
-- 06-optimisation.sql - Index et optimisation EXPLAIN ANALYZE
--
-- Démarche :
--   1. Mesurer les performances initiales (sans index FK)
--   2. Identifier les goulots : Seq Scan sur les grandes tables
--   3. Créer des index ciblés sur les colonnes de JOIN et de filtre
--   4. Mesurer après : comparer les temps d'exécution
--
-- ATTENTION : un index coûte de l'espace disque et ralentit les INSERT/UPDATE.
-- On indexe uniquement ce qui est réellement utilisé.
-- ============================================================

-- ============================================================
-- MESURE AVANT - baseline sans index FK
-- ============================================================

EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_customer_features;

-- ============================================================
-- INDEX 1 : orders.customer_id (clé étrangère)
--
-- Justification : la table orders est jointe à customers dans 4 CTEs
-- sur la condition customers.customer_id = orders.customer_id.
-- Sans index, PostgreSQL fait un Seq Scan complet de orders (99k lignes)
-- pour chaque évaluation. L'index B-tree permet une recherche directe.
-- ============================================================

CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- ============================================================
-- INDEX 2 : order_items.order_id (clé étrangère)
--
-- Justification : order_items (112k lignes) est joint à orders dans
-- les CTEs commandes et features_diversite. Sans index, Seq Scan
-- de toute la table pour chaque order_id recherché.
-- ============================================================

CREATE INDEX idx_order_items_order_id ON order_items(order_id);

-- ============================================================
-- INDEX 3 : order_reviews.order_id (clé étrangère)
--
-- Justification : order_reviews (98k lignes) est jointe à orders
-- dans features_satisfaction. Le LEFT JOIN nécessite de scanner
-- toutes les reviews pour chaque order_id sans index.
-- ============================================================

CREATE INDEX idx_order_reviews_order_id ON order_reviews(order_id);

-- ============================================================
-- INDEX 4 : customers.customer_unique_id
--
-- Justification : la vue GROUP BY customer_unique_id dans 5 CTEs
-- différentes, et joint les CTEs via USING (customer_unique_id).
-- Index pour accélérer les tris et regroupements.
-- ============================================================

CREATE INDEX idx_customers_unique_id ON customers(customer_unique_id);

-- ============================================================
-- INDEX 5 (partiel) : orders.customer_id WHERE order_status = 'delivered'
--
-- Justification : 97% des requêtes filtrent sur order_status = 'delivered'.
-- Un index partiel ne contient que ces lignes (96k sur 99k) → plus petit
-- et utilisable directement sans Recheck Cond sur le filtre.
-- ============================================================

CREATE INDEX idx_orders_delivered ON orders(customer_id)
    WHERE order_status = 'delivered';

-- ============================================================
-- ANALYZE - Met à jour les statistiques du planner
-- ============================================================

ANALYZE customers;
ANALYZE orders;
ANALYZE order_items;
ANALYZE order_reviews;

-- ============================================================
-- MESURE APRÈS - avec les index
-- ============================================================

EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_customer_features;

-- ============================================================
-- BONUS : MATERIALIZED VIEW pour le pipeline ML
--
-- Avantage  : SELECT * passe de ~700ms à ~4ms (gain ×175)
--             Lookup 1 client : 314ms → 0.13ms (gain ×2400)
-- Coût      : données non temps réel, REFRESH manuel requis
-- Use case  : parfait pour un pipeline ML qui interroge en masse
-- ============================================================

DROP MATERIALIZED VIEW IF EXISTS mv_customer_features;

CREATE MATERIALIZED VIEW mv_customer_features AS
SELECT * FROM v_customer_features;

-- Index unique sur la PK pour lookups instantanés
CREATE UNIQUE INDEX idx_mv_customer_unique_id
    ON mv_customer_features(customer_unique_id);

-- Index sur recency_days pour requêtes de segmentation churn
CREATE INDEX idx_mv_recency ON mv_customer_features(recency_days);

-- Pour rafraîchir après ingestion de nouvelles données :
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_customer_features;

-- Mesure de la lecture matérialisée
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM mv_customer_features;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM mv_customer_features
WHERE customer_unique_id = '083ca1aa470c280236380973a48f77c6';

-- ============================================================
-- Vérification finale : liste des index créés
-- ============================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('orders', 'order_items', 'order_reviews', 'customers',
                    'mv_customer_features')
ORDER BY tablename, indexname;
