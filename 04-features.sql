-- ============================================================
-- 04-features.sql - Feature engineering avec CTEs et Window Functions
--
-- Objectif : construire les signaux comportementaux par client
-- pour alimenter un modèle de prédiction de churn.
--
-- Date de référence ("aujourd'hui") : 2018-10-17
-- = dernière commande du dataset. On se place à cette date
-- pour calculer la récence de chaque client.
--
-- 9 features couvrant 4 axes :
--   RFM         : recency_days, frequency, total_spent, avg_basket
--   Tendance    : basket_trend, avg_days_between_orders
--   Satisfaction: avg_review_score, pct_negative_reviews
--   Engagement  : category_diversity
-- ============================================================

-- ============================================================
-- CTE 1 : montant par commande par client
-- On part de la jointure customers → orders → order_items
-- et on GROUP BY par commande pour avoir le total de chaque commande.
-- ============================================================

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

-- ============================================================
-- CTE 2 : Window Functions - LAG + ROW_NUMBER sur les commandes
-- Pour chaque commande d'un client, on calcule :
--   - le numéro de commande (1ère, 2ème, 3ème...)
--   - le montant de la commande précédente (LAG)
--   - la date de la commande précédente (LAG)
-- ============================================================

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

-- ============================================================
-- CTE 3 : features RFM basiques (GROUP BY sur customer_unique_id)
-- Récence, Fréquence, Montant total, Panier moyen
-- ============================================================

features_rfm AS (
    SELECT
        customer_unique_id,

        -- RÉCENCE : jours depuis la dernière commande
        '2018-10-17'::DATE - MAX(order_purchase_timestamp)::DATE
            AS recency_days,

        -- FRÉQUENCE : nombre de commandes livrées
        COUNT(*) AS frequency,

        -- MONTANT TOTAL
        ROUND(SUM(montant_commande), 2) AS total_spent,

        -- PANIER MOYEN par commande
        ROUND(AVG(montant_commande), 2) AS avg_basket

    FROM commandes
    GROUP BY customer_unique_id
),

-- ============================================================
-- CTE 4 : feature TENDANCE du panier (basée sur LAG)
-- Moyenne de (montant_commande - montant_precedent) par client.
-- Positif = panier en hausse, négatif = en baisse.
-- NULL pour les clients avec 1 seule commande.
-- ============================================================

features_tendance AS (
    SELECT
        customer_unique_id,
        ROUND(AVG(montant_commande - montant_precedent), 2) AS basket_trend
    FROM commandes_enrichies
    WHERE montant_precedent IS NOT NULL
    GROUP BY customer_unique_id
),

-- ============================================================
-- CTE 5 : feature DÉLAI INTER-COMMANDES (basée sur LAG dates)
-- Nombre moyen de jours entre deux commandes successives.
-- NULL pour les clients avec 1 seule commande.
-- ============================================================

features_delai AS (
    -- Cast en ::DATE pour soustraire deux dates : retourne directement un INTEGER en jours.
    -- (EXTRACT(DAY FROM interval) ne retourne que la composante "jours" de l'intervalle,
    --  pas le total - par exemple "1 mois 5 jours" donnerait 5 au lieu de 35.)
    SELECT
        customer_unique_id,
        ROUND(AVG(
            order_purchase_timestamp::DATE - date_precedente::DATE
        ), 1) AS avg_days_between_orders
    FROM commandes_enrichies
    WHERE date_precedente IS NOT NULL
    GROUP BY customer_unique_id
),

-- ============================================================
-- CTE 6 : features SATISFACTION (reviews)
-- Score moyen et pourcentage de reviews négatives (score <= 2).
-- LEFT JOIN car certains clients n'ont pas laissé de review.
-- FILTER compte sous condition, NULLIF protège contre la division par zéro
-- quand un client n'a aucune review.
-- ============================================================

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

-- ============================================================
-- CTE 7 : feature DIVERSITÉ CATÉGORIELLE
-- Nombre de catégories de produits distinctes achetées.
-- ============================================================

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

-- ============================================================
-- Requête finale : assemblage de toutes les features
-- ============================================================

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
LEFT JOIN features_diversite div USING (customer_unique_id)
ORDER BY r.total_spent DESC
LIMIT 20;
