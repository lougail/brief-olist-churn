# Schéma de la base de données Olist

## Vue d'ensemble

Base relationnelle modélisant un e-commerce brésilien (2016-2018) :
- **8 tables** au total (7 entités métier + 1 table de traduction)
- **Volume** : ~100k commandes, ~99k clients, ~112k items, ~98k reviews
- **Convention** : tous les identifiants sont des hashes `VARCHAR(32)`

## Diagramme entité-relation

```mermaid
erDiagram
    customers ||--o{ orders : "passe"
    orders ||--o{ order_items : "contient"
    orders ||--o{ order_payments : "paye via"
    orders ||--o{ order_reviews : "evalue par"
    products ||--o{ order_items : "vendu dans"
    sellers ||--o{ order_items : "vend"
    products }o--|| product_category_translation : "traduit par"

    customers {
        VARCHAR customer_id PK
        VARCHAR customer_unique_id "vrai identifiant client"
        VARCHAR customer_zip_code_prefix
        VARCHAR customer_city
        VARCHAR customer_state
    }

    orders {
        VARCHAR order_id PK
        VARCHAR customer_id FK
        VARCHAR order_status "delivered / canceled / ..."
        TIMESTAMP order_purchase_timestamp
        TIMESTAMP order_approved_at
        TIMESTAMP order_delivered_carrier_date
        TIMESTAMP order_delivered_customer_date
        TIMESTAMP order_estimated_delivery_date
    }

    order_items {
        VARCHAR order_id PK,FK
        INT order_item_id PK
        VARCHAR product_id FK
        VARCHAR seller_id FK
        NUMERIC price
        NUMERIC freight_value
    }

    order_payments {
        VARCHAR order_id PK,FK
        INT payment_sequential PK
        VARCHAR payment_type
        INT payment_installments
        NUMERIC payment_value
    }

    order_reviews {
        VARCHAR review_id PK
        VARCHAR order_id FK
        SMALLINT review_score "1-5"
        TEXT review_comment_title
        TEXT review_comment_message
        TIMESTAMP review_creation_date
    }

    products {
        VARCHAR product_id PK
        VARCHAR product_category_name FK
        INT product_name_lenght
        INT product_weight_g
    }

    sellers {
        VARCHAR seller_id PK
        VARCHAR seller_zip_code_prefix
        VARCHAR seller_city
        VARCHAR seller_state
    }

    product_category_translation {
        VARCHAR product_category_name PK
        VARCHAR product_category_name_english
    }
```

## Le piège `customer_id` vs `customer_unique_id`

Point crucial du dataset : Olist **régénère un `customer_id` à chaque commande**.
Pour identifier un vrai client (et calculer ses features), il faut utiliser `customer_unique_id`.

| Colonne | Nombre de valeurs distinctes | Sens |
|---------|-----------------------------|------|
| `customer_id` | 99 441 | Identifiant **par commande** (techniquement = 1 commande) |
| `customer_unique_id` | 96 096 | Identifiant **par personne** (le vrai client) |

C'est pour ça que tous les `GROUP BY` du feature engineering portent sur `customer_unique_id`.

## Vue analytique `v_customer_features`

Vue construite au-dessus de ces tables, agrégeant 9 features par client :

```mermaid
graph LR
    A[customers] --> V[v_customer_features]
    B[orders] --> V
    C[order_items] --> V
    D[order_reviews] --> V
    E[products] --> V
    V --> ML[Pipeline ML<br/>predict churn]
```

Colonnes de la vue :
- `customer_unique_id` - clé primaire logique
- `recency_days` - jours depuis la dernière commande
- `frequency` - nombre de commandes
- `total_spent` - montant total dépensé
- `avg_basket` - panier moyen
- `basket_trend` - évolution du panier (positif = en hausse)
- `avg_days_between_orders` - fréquence d'achat
- `avg_review_score` - satisfaction moyenne
- `pct_negative_reviews` - pourcentage 0-100 des reviews ≤ 2
- `category_diversity` - diversité catégorielle
