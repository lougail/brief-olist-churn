# SQL Avancé - Feature Engineering pour la Prédiction de Churn Client

> Projet pédagogique Simplon - Brief RNCP Développeur IA
> Construction d'un pipeline SQL de feature engineering pour la prédiction de churn,
> à partir du dataset e-commerce brésilien **Olist** (~100k commandes, 2016-2018).

## Objectif métier

Détecter les clients à risque de churn (= ne plus jamais commander) **avant** qu'ils ne partent,
pour pouvoir lancer des actions de rétention ciblées.

Le livrable n'est pas un modèle ML, c'est la base de données qui servira ensuite à entraîner ce modèle.
Concrètement : une vue `v_customer_features` où chaque ligne représente un client avec ses indicateurs.

## Stack technique

| Composant | Choix | Pourquoi |
|-----------|-------|----------|
| **SGBD** | PostgreSQL 16 | SQL avancé (CTEs, Window Functions, FILTER, MATERIALIZED VIEW) |
| **Conteneurisation** | Docker Compose | Environnement reproductible sur n'importe quelle machine |
| **Données** | CSV Kaggle (Olist) | ~120 MB, 9 fichiers, normalisés en 8 tables |
| **Client SQL** | TablePlus (ou DBeaver, psql) | Au choix, visualisation tabulaire |

## Installation

### Prérequis
- Docker Desktop installé et lancé
- ~500 MB d'espace disque libre

### Étapes

1. **Télécharger les données** depuis Kaggle :
   https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
   Décompresser dans `./data/` (9 fichiers `.csv` attendus).

2. **Démarrer la base PostgreSQL** :
   ```bash
   docker compose up -d
   ```
   Le schéma (`01-schema.sql`) est joué automatiquement au premier démarrage
   via le hook `docker-entrypoint-initdb.d`.

3. **Exécuter les scripts dans l'ordre** :
   ```bash
   docker exec -i olist-postgres psql -U olist -d olist < 02-import.sql
   docker exec -i olist-postgres psql -U olist -d olist < 03-nettoyage.sql
   docker exec -i olist-postgres psql -U olist -d olist < 04-features.sql
   docker exec -i olist-postgres psql -U olist -d olist < 05-vue-finale.sql
   docker exec -i olist-postgres psql -U olist -d olist < 06-optimisation.sql
   ```

4. **Se connecter avec un client GUI** (TablePlus, DBeaver) :
   - Host : `localhost`
   - Port : `5432`
   - User : `olist`
   - Password : `olist`
   - Database : `olist`

5. **Requêter la vue** :
   ```sql
   SELECT * FROM v_customer_features LIMIT 10;
   ```

## Structure du projet

```
brief-olist-churn/
├── docker-compose.yml      # Stack PostgreSQL 16
├── data/                   # CSV Olist (non versionnés, à télécharger)
│
├── 01-schema.sql           # 8 tables, PKs, FKs, CHECK constraints
├── 02-import.sql           # COPY des CSV (avec gestion BOM + dedup reviews)
├── 03-nettoyage.sql        # 5 anomalies de qualité corrigées
├── 04-features.sql         # 9 features via 7 CTEs + Window Functions
├── 05-vue-finale.sql       # CREATE VIEW v_customer_features
├── 06-optimisation.sql     # 5 index + MATERIALIZED VIEW (bonus)
│
├── schema.md               # Diagramme ER de la base (mermaid)
└── README.md
```

## Schéma de la base

Voir [`schema.md`](./schema.md) pour le diagramme ER complet et le détail du piège
`customer_id` vs `customer_unique_id`.

**Résumé** : 8 tables liées par des FKs, avec une convention `VARCHAR(32)` pour tous les
identifiants (hashes). Le client n'est identifié de façon stable que par `customer_unique_id`
(et **pas** par `customer_id`, qui est régénéré à chaque commande).

## Les 9 features et leur justification métier

| Feature | Calcul | Pourquoi pour le churn ? |
|---------|--------|--------------------------|
| `recency_days` | Jours depuis la dernière commande (ref. `2018-10-17`) | Un client qui n'a rien commandé depuis longtemps est probablement parti |
| `frequency` | Nombre de commandes livrées | Un client qui ne commande qu'une fois est plus à risque qu'un client régulier |
| `total_spent` | Somme de `price + freight_value` sur toutes les commandes | Permet de prioriser les gros clients dans les actions de rétention |
| `avg_basket` | Panier moyen | Donne le profil d'achat type |
| `basket_trend` | Moyenne de `(montant_n - montant_n-1)` via `LAG` | Si le panier baisse au fil des commandes, le client se désengage |
| `avg_days_between_orders` | Moyenne des écarts entre commandes successives via `LAG` | Si le délai habituel est dépassé, c'est un signal |
| `avg_review_score` | Note moyenne des reviews | Un client insatisfait part plus vite |
| `pct_negative_reviews` | Pourcentage (0-100) des reviews ≤ 2, via `FILTER` | Capte les clients déçus même si la moyenne reste correcte |
| `category_diversity` | Nombre de catégories distinctes achetées | Un client qui achète dans plusieurs catégories est plus ancré sur la plateforme |

J'ai regroupé les features en 4 familles :
- **RFM** (Récence, Fréquence, Montant) : c'est le cadre classique de la segmentation client, features 1-4
- **Tendance** : évolution dans le temps, features 5-6
- **Satisfaction** : ce que pense le client, features 7-8
- **Engagement** : feature 9

## Concepts SQL avancés utilisés

| Concept | Où ? | Pour quoi faire ? |
|---------|------|-------------------|
| **CTE** (`WITH ... AS`) | `04-features.sql`, `05-vue-finale.sql` | Découper une grosse requête en étapes nommées et lisibles |
| **Window Function `LAG`** | CTE `commandes_enrichies` | Récupérer la valeur de la ligne précédente (montant N-1, date N-1) sans self-join |
| **Window Function `ROW_NUMBER`** | CTE `commandes_enrichies` | Numéroter les commandes par client dans l'ordre chronologique |
| **`PARTITION BY`** | Toutes les window functions | Redémarrer la fenêtre à chaque nouveau client |
| **`FILTER (WHERE ...)`** | `pct_negative_reviews` | Compter seulement les reviews ≤ 2 |
| **`NULLIF`** | `pct_negative_reviews` | Eviter la division par zéro quand un client n'a pas de review |
| **`DISTINCT ON`** | `02-import.sql` | Garder une seule ligne par `review_id` (la plus récente) |
| **CHECK constraints** | `01-schema.sql` | Empêcher les valeurs invalides à l'insertion (prix ≥ 0, score 1-5) |
| **Index partiel** | `idx_orders_delivered` | Index seulement sur les commandes `delivered` |
| **`MATERIALIZED VIEW`** | `06-optimisation.sql` | Stocker le résultat précalculé de la vue, pour gagner du temps en lecture |

## Qualité des données (corrections appliquées)

Le script `03-nettoyage.sql` traite 5 anomalies identifiées dans le dataset :

1. **949 reviews en doublon** sur `review_id` → résolu à l'import par `DISTINCT ON`, on garde la review la plus récente
2. **8 commandes `delivered` sans date de livraison** → imputation par `COALESCE(carrier_date + 7j, purchase + 14j)`
3. **610 produits sans catégorie** → reclassés `'sem_categoria'`
4. **2 catégories sans traduction** (`portateis_cozinha...` et `pc_gamer`) → ajout manuel via `INSERT`, plus la traduction de `sem_categoria` créée à l'étape précédente
5. **9 paiements à zéro** → conservés (vouchers + commandes annulées, comportement légitime)

## Performances mesurées

J'ai mesuré avec `EXPLAIN (ANALYZE, BUFFERS)`. Les temps varient un peu d'une exécution à l'autre, ordres de grandeur observés :

| Requête | Sans index | Avec index | Avec `MATERIALIZED VIEW` |
|---------|-----------|-----------|--------------------------|
| `SELECT * FROM v_customer_features` | ~700 ms | ~700 ms | quelques ms |
| Lookup par `customer_unique_id` | ~300 ms | ~300 ms | < 1 ms |

L'écart entre "sans index" et "avec index" est faible parce que la requête lit toutes les lignes (pas de filtre). C'est la materialized view qui apporte le vrai gain : on stocke le résultat précalculé une fois pour toutes.

## Pistes pour la suite

La vue est prête à être consommée par un modèle de prédiction de churn (par exemple scikit-learn ou XGBoost). Un dashboard au-dessus de la vue (Streamlit) serait aussi un bon prolongement.

## Auteur

Louis Gaillard - Simplon, formation Développeur IA (RNCP)
