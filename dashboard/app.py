"""
Dashboard Olist Churn - visualisation de la vue v_customer_features.
Lance avec : streamlit run dashboard/app.py
"""

import pandas as pd
import plotly.express as px
import streamlit as st
from sqlalchemy import create_engine, text

# ---------------------------------------------------------------------------
# Connexion a la BDD locale Docker
# En prod on utiliserait st.secrets, ici c'est une base locale donc OK.
# ---------------------------------------------------------------------------

DB_URL = "postgresql+psycopg2://olist:olist@localhost:5432/olist"


@st.cache_resource
def get_engine():
    return create_engine(DB_URL)


@st.cache_data(ttl=300)
def run_query(sql: str) -> pd.DataFrame:
    return pd.read_sql(text(sql), get_engine())


# ---------------------------------------------------------------------------
# Mise en page
# ---------------------------------------------------------------------------

st.set_page_config(
    page_title="Olist Churn - Features client",
    layout="wide",
)

st.title("Olist - Analyse des features client")
st.caption(
    "Visualisation de la vue analytique `v_customer_features` "
    "construite a partir du dataset Olist (~100k commandes 2016-2018)."
)

# ---------------------------------------------------------------------------
# KPIs en haut
# ---------------------------------------------------------------------------

kpis = run_query("""
    SELECT
        COUNT(*) AS nb_clients,
        COUNT(*) FILTER (WHERE frequency > 1) AS nb_recurrents,
        ROUND(SUM(total_spent), 0) AS revenue_total,
        ROUND(AVG(avg_review_score), 2) AS score_moyen
    FROM mv_customer_features
""").iloc[0]

col1, col2, col3, col4 = st.columns(4)
col1.metric("Clients uniques", f"{int(kpis.nb_clients):,}".replace(",", " "))
col2.metric(
    "Clients recurrents",
    f"{int(kpis.nb_recurrents):,}".replace(",", " "),
    delta=f"{kpis.nb_recurrents / kpis.nb_clients * 100:.1f}% du total",
    delta_color="off",
)
col3.metric("Revenue total", f"{int(kpis.revenue_total):,} R$".replace(",", " "))
col4.metric("Note moyenne", f"{kpis.score_moyen:.2f} / 5")

st.divider()

# ---------------------------------------------------------------------------
# Section 1 : RFM (Recence, Frequence, Montant)
# ---------------------------------------------------------------------------

st.header("1. Profil RFM des clients")

col_l, col_r = st.columns(2)

with col_l:
    st.subheader("Distribution de la recence")
    recency_buckets = run_query("""
        SELECT
            CASE
                WHEN recency_days <= 30  THEN '0-30j (actifs)'
                WHEN recency_days <= 90  THEN '31-90j'
                WHEN recency_days <= 180 THEN '91-180j'
                WHEN recency_days <= 365 THEN '181-365j'
                ELSE '> 365j (perdus ?)'
            END AS bucket,
            COUNT(*) AS nb_clients
        FROM mv_customer_features
        GROUP BY bucket
        ORDER BY MIN(recency_days)
    """)
    fig = px.bar(
        recency_buckets,
        x="bucket",
        y="nb_clients",
        labels={"bucket": "Recence", "nb_clients": "Nombre de clients"},
        color="bucket",
        color_discrete_sequence=px.colors.sequential.Reds_r,
    )
    fig.update_layout(showlegend=False, height=350)
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "Plus la barre a droite est haute, plus on a de clients silencieux "
        "depuis longtemps - candidats au churn."
    )

with col_r:
    st.subheader("Distribution du panier moyen")
    panier = run_query("""
        SELECT avg_basket
        FROM mv_customer_features
        WHERE avg_basket < 1000
    """)
    fig = px.histogram(
        panier,
        x="avg_basket",
        nbins=50,
        labels={"avg_basket": "Panier moyen (R$)"},
    )
    fig.update_layout(height=350, yaxis_title="Nombre de clients")
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "Distribution tronquee a 1000 R$ pour la lisibilite "
        "(quelques outliers > 4000 R$)."
    )

# Distribution de la frequence
st.subheader("Distribution de la frequence d'achat")
frequency = run_query("""
    SELECT
        CASE WHEN frequency >= 5 THEN '5+' ELSE frequency::TEXT END AS freq,
        COUNT(*) AS nb_clients
    FROM mv_customer_features
    GROUP BY freq
    ORDER BY MIN(frequency)
""")
fig = px.bar(
    frequency,
    x="freq",
    y="nb_clients",
    labels={"freq": "Nombre de commandes", "nb_clients": "Nombre de clients"},
    text="nb_clients",
)
fig.update_traces(textposition="outside")
fig.update_layout(height=300)
st.plotly_chart(fig, use_container_width=True)
st.caption(
    "La grande majorite n'a commande qu'une seule fois - c'est la difficulte "
    "principale de la prediction de churn sur ce dataset."
)

st.divider()

# ---------------------------------------------------------------------------
# Section 2 : Satisfaction
# ---------------------------------------------------------------------------

st.header("2. Satisfaction client")

col_l, col_r = st.columns(2)

with col_l:
    st.subheader("Repartition des notes moyennes")
    scores = run_query("""
        SELECT
            ROUND(avg_review_score) AS note,
            COUNT(*) AS nb_clients
        FROM mv_customer_features
        WHERE avg_review_score IS NOT NULL
        GROUP BY note
        ORDER BY note
    """)
    fig = px.bar(
        scores,
        x="note",
        y="nb_clients",
        labels={"note": "Note moyenne arrondie", "nb_clients": "Nombre de clients"},
        color="note",
        color_continuous_scale="RdYlGn",
    )
    fig.update_layout(height=350, coloraxis_showscale=False)
    st.plotly_chart(fig, use_container_width=True)

with col_r:
    st.subheader("Pourcentage de reviews negatives")
    neg = run_query("""
        SELECT pct_negative_reviews
        FROM mv_customer_features
        WHERE pct_negative_reviews IS NOT NULL
    """)
    fig = px.histogram(
        neg,
        x="pct_negative_reviews",
        nbins=20,
        labels={"pct_negative_reviews": "% de reviews <= 2"},
    )
    fig.update_layout(height=350, yaxis_title="Nombre de clients")
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "La majorite des clients sont a 0% (aucune review negative) "
        "mais un pic a 100% revele les clients deja braques."
    )

st.divider()

# ---------------------------------------------------------------------------
# Section 3 : Identification des clients a risque
# ---------------------------------------------------------------------------

st.header("3. Clients a risque de churn")

st.markdown(
    "**Definition retenue** : clients qui n'ont pas commande depuis "
    "**plus de 6 mois** ET dont le **panier total depasse 200 R$** "
    "(donc des clients qui ont eu de la valeur mais qu'on est en train de perdre)."
)

risk_kpis = run_query("""
    SELECT
        COUNT(*) AS nb_a_risque,
        ROUND(SUM(total_spent), 0) AS revenue_perdu,
        ROUND(AVG(recency_days), 0) AS recence_moyenne
    FROM mv_customer_features
    WHERE recency_days > 180
      AND total_spent > 200
""").iloc[0]

c1, c2, c3 = st.columns(3)
c1.metric(
    "Clients identifies a risque",
    f"{int(risk_kpis.nb_a_risque):,}".replace(",", " "),
)
c2.metric(
    "Revenue cumule de ces clients",
    f"{int(risk_kpis.revenue_perdu):,} R$".replace(",", " "),
)
c3.metric(
    "Recence moyenne du groupe",
    f"{int(risk_kpis.recence_moyenne)} jours",
)

st.subheader("Top 20 clients a risque par valeur economique")
top_risk = run_query("""
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        total_spent,
        avg_review_score,
        pct_negative_reviews
    FROM mv_customer_features
    WHERE recency_days > 180
      AND total_spent > 200
    ORDER BY total_spent DESC
    LIMIT 20
""")
st.dataframe(top_risk, use_container_width=True, hide_index=True)
st.caption(
    "Ce sont les clients que le marketing devrait contacter en priorite "
    "(grosse valeur economique, silencieux depuis > 6 mois)."
)

st.divider()

# ---------------------------------------------------------------------------
# Section 4 : Geographie (bonus, via jointure customers)
# ---------------------------------------------------------------------------

st.header("4. Repartition geographique")

geo = run_query("""
    SELECT
        c.customer_state AS state,
        COUNT(DISTINCT v.customer_unique_id) AS nb_clients,
        ROUND(AVG(v.total_spent), 2) AS panier_moyen
    FROM mv_customer_features v
    JOIN customers c USING (customer_unique_id)
    GROUP BY c.customer_state
    ORDER BY nb_clients DESC
    LIMIT 10
""")

col_l, col_r = st.columns(2)
with col_l:
    st.subheader("Top 10 etats par nombre de clients")
    fig = px.bar(
        geo,
        x="state",
        y="nb_clients",
        labels={"state": "Etat", "nb_clients": "Nombre de clients"},
        text="nb_clients",
    )
    fig.update_traces(textposition="outside")
    fig.update_layout(height=350)
    st.plotly_chart(fig, use_container_width=True)

with col_r:
    st.subheader("Panier moyen par etat (top 10)")
    fig = px.bar(
        geo.sort_values("panier_moyen", ascending=False),
        x="state",
        y="panier_moyen",
        labels={"state": "Etat", "panier_moyen": "Total spent moyen (R$)"},
        color="panier_moyen",
        color_continuous_scale="Blues",
    )
    fig.update_layout(height=350, coloraxis_showscale=False)
    st.plotly_chart(fig, use_container_width=True)

st.caption(
    "Sao Paulo (SP) concentre l'essentiel de la base. "
    "Les etats moins peuples ont parfois des paniers moyens plus eleves "
    "(produits importes plus chers ?)."
)

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

st.divider()
st.caption(
    "Source : vue materialisee `mv_customer_features` "
    "(93 358 clients, dataset Olist 2016-2018). "
    "Cache Streamlit : 5 minutes."
)
