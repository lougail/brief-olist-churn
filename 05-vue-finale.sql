-- ============================================================
-- 05-vue-finale.sql - Création de la vue analytique v_customer_features
--
-- Cette vue consolide toutes les features client pour le pipeline ML.
-- Chaque ligne = 1 customer_unique_id avec toutes ses métriques RFM,
-- comportementales, satisfaction et diversité.
--
-- Cible : équipe data science, interrogée par SELECT * FROM v_customer_features
-- ============================================================

DROP VIEW IF EXISTS v_customer_features;

CREATE VIEW v_customer_features AS

WITH commandes AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS montant_commande,
        COUNT(oi.order_item_id) AS nb_articles
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
),

commandes_enrichies AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS numero_commande,

        LAG(montant_commande) OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS montant_precedent,

        LAG(order_purchase_timestamp) OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS date_precedente
    FROM commandes
),

features_rfm AS (
    SELECT
        customer_unique_id,
        '2018-10-17'::DATE - MAX(order_purchase_timestamp)::DATE AS recency_days,
        COUNT(*) AS frequency,
        ROUND(SUM(montant_commande), 2) AS total_spent,
        ROUND(AVG(montant_commande), 2) AS avg_basket
    FROM commandes
    GROUP BY customer_unique_id
),

features_tendance AS (
    SELECT
        customer_unique_id,
        ROUND(AVG(montant_commande - montant_precedent), 2) AS basket_trend
    FROM commandes_enrichies
    WHERE montant_precedent IS NOT NULL
    GROUP BY customer_unique_id
),

features_delai AS (
    SELECT
        customer_unique_id,
        ROUND(AVG(
            order_purchase_timestamp::DATE - date_precedente::DATE
        ), 1) AS avg_days_between_orders
    FROM commandes_enrichies
    WHERE date_precedente IS NOT NULL
    GROUP BY customer_unique_id
),

features_satisfaction AS (
    SELECT
        c.customer_unique_id,
        ROUND(AVG(r.review_score), 2) AS avg_review_score,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2)
            / NULLIF(COUNT(r.review_score), 0),
            1
        ) AS pct_negative_reviews
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

features_diversite AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT p.product_category_name) AS category_diversity
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)

SELECT
    r.customer_unique_id,
    r.recency_days,
    r.frequency,
    r.total_spent,
    r.avg_basket,
    t.basket_trend,
    d.avg_days_between_orders,
    s.avg_review_score,
    s.pct_negative_reviews,
    div.category_diversity
FROM features_rfm r
LEFT JOIN features_tendance t USING (customer_unique_id)
LEFT JOIN features_delai d USING (customer_unique_id)
LEFT JOIN features_satisfaction s USING (customer_unique_id)
LEFT JOIN features_diversite div USING (customer_unique_id);

-- ============================================================
-- Vérification : aperçu et comptage
-- ============================================================

SELECT * FROM v_customer_features LIMIT 10;

SELECT
    COUNT(*) AS nb_clients,
    COUNT(*) FILTER (WHERE frequency > 1) AS clients_recurrents,
    ROUND(AVG(recency_days), 1) AS recency_moyenne,
    ROUND(AVG(total_spent), 2) AS depense_moyenne
FROM v_customer_features;
