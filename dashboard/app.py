"""
Dashboard Olist Churn - visualisation de la vue v_customer_features.
Lance avec : streamlit run dashboard/app.py
"""

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
from sqlalchemy import create_engine, text

# ---------------------------------------------------------------------------
# Connexion a la BDD locale Docker
# ---------------------------------------------------------------------------

DB_URL = "postgresql+psycopg2://olist:olist@localhost:5432/olist"


@st.cache_resource
def get_engine():
    return create_engine(DB_URL)


@st.cache_data(ttl=300)
def run_query(sql: str) -> pd.DataFrame:
    return pd.read_sql(text(sql), get_engine())


# ---------------------------------------------------------------------------
# Theme et palette
# ---------------------------------------------------------------------------

PRIMARY = "#1f4e79"
DANGER = "#c5454f"
WARNING = "#e8a13b"
SUCCESS = "#3a8c5c"
NEUTRAL = "#6b7280"
SOFT_BG = "#f7f8fa"

PLOTLY_TEMPLATE = "plotly_white"

PALETTE_RFM = [SUCCESS, "#7eb37a", WARNING, "#e07a52", DANGER]
PALETTE_NOTES = [DANGER, "#e07a52", WARNING, "#7eb37a", SUCCESS]

CUSTOM_CSS = """
<style>
    /* Header principal */
    .main-title {
        font-size: 2.3rem;
        font-weight: 700;
        color: #1f4e79;
        margin-bottom: 0;
        padding-bottom: 0;
    }
    .main-subtitle {
        color: #6b7280;
        font-size: 1rem;
        margin-top: 0.2rem;
        margin-bottom: 1.5rem;
    }
    /* Sections */
    h2 {
        color: #1f4e79;
        border-bottom: 2px solid #e5e7eb;
        padding-bottom: 0.4rem;
        margin-top: 2rem;
    }
    h3 {
        color: #374151;
        font-size: 1.05rem;
        font-weight: 600;
        margin-top: 0.8rem;
    }
    /* KPI cards (st.metric) */
    [data-testid="stMetric"] {
        background-color: #f7f8fa;
        border: 1px solid #e5e7eb;
        border-radius: 10px;
        padding: 1rem 1.2rem;
        box-shadow: 0 1px 3px rgba(0,0,0,0.04);
    }
    [data-testid="stMetric"] [data-testid="stMetricLabel"] {
        color: #6b7280;
        font-size: 0.85rem;
        font-weight: 500;
        text-transform: uppercase;
        letter-spacing: 0.03em;
    }
    [data-testid="stMetric"] [data-testid="stMetricValue"] {
        color: #1f4e79;
        font-weight: 700;
    }
    /* KPI cards en danger : fond rouge clair */
    [data-testid="stMetric"].metric-danger {
        background-color: #fef2f2;
        border-color: #fecaca;
    }
    /* Bloc d'alerte custom */
    .alert-box {
        background: linear-gradient(135deg, #fef3f2 0%, #fff7ed 100%);
        border-left: 4px solid #c5454f;
        padding: 1rem 1.2rem;
        border-radius: 6px;
        margin: 1rem 0;
    }
    .alert-box-title {
        color: #c5454f;
        font-weight: 700;
        font-size: 0.95rem;
        margin-bottom: 0.3rem;
    }
    /* Captions plus discretes */
    .stCaption {
        color: #9ca3af !important;
        font-size: 0.8rem !important;
    }
    /* Reduire le padding global pour densifier */
    .block-container {
        padding-top: 2rem;
        padding-bottom: 2rem;
        max-width: 1300px;
    }
</style>
"""


def styled_plot(fig, height=320):
    """Style commun a tous les graphes Plotly."""
    fig.update_layout(
        template=PLOTLY_TEMPLATE,
        height=height,
        margin=dict(l=20, r=20, t=30, b=40),
        font=dict(family="-apple-system, sans-serif", size=12, color="#374151"),
        showlegend=False,
        plot_bgcolor="white",
        paper_bgcolor="white",
        xaxis=dict(showgrid=False, linecolor="#e5e7eb"),
        yaxis=dict(gridcolor="#f3f4f6", linecolor="#e5e7eb"),
    )
    return fig


# ---------------------------------------------------------------------------
# Mise en page
# ---------------------------------------------------------------------------

st.set_page_config(
    page_title="Olist Churn - Features client",
    layout="wide",
    initial_sidebar_state="collapsed",
)

st.markdown(CUSTOM_CSS, unsafe_allow_html=True)

st.markdown(
    """
    <div class="main-title">Olist - Analyse des features client</div>
    <div class="main-subtitle">
        Visualisation de la vue analytique <code>v_customer_features</code>
        construite a partir du dataset Olist (~100k commandes, 2016-2018).
    </div>
    """,
    unsafe_allow_html=True,
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

c1, c2, c3, c4 = st.columns(4)
with c1:
    st.metric("Clients uniques", f"{int(kpis.nb_clients):,}".replace(",", " "))
with c2:
    st.metric(
        "Clients recurrents",
        f"{int(kpis.nb_recurrents):,}".replace(",", " "),
        delta=f"{kpis.nb_recurrents / kpis.nb_clients * 100:.1f} % du total",
        delta_color="off",
    )
with c3:
    st.metric("Revenue total", f"{int(kpis.revenue_total / 1_000_000):,} M R$")
with c4:
    st.metric("Note moyenne", f"{kpis.score_moyen:.2f} / 5")

# ---------------------------------------------------------------------------
# Section 1 : RFM
# ---------------------------------------------------------------------------

st.header("Profil RFM des clients")

col_l, col_r = st.columns(2)

with col_l:
    st.markdown("##### Distribution de la recence")
    recency = run_query("""
        SELECT
            CASE
                WHEN recency_days <= 30  THEN '0-30j'
                WHEN recency_days <= 90  THEN '31-90j'
                WHEN recency_days <= 180 THEN '91-180j'
                WHEN recency_days <= 365 THEN '181-365j'
                ELSE '> 365j'
            END AS bucket,
            COUNT(*) AS nb_clients
        FROM mv_customer_features
        GROUP BY bucket
        ORDER BY MIN(recency_days)
    """)
    fig = px.bar(
        recency,
        x="bucket",
        y="nb_clients",
        color="bucket",
        color_discrete_sequence=PALETTE_RFM[:len(recency)],
        text="nb_clients",
    )
    fig.update_traces(
        texttemplate="%{text:,d}".replace(",", " "),
        textposition="outside",
    )
    fig.update_layout(xaxis_title="", yaxis_title="")
    st.plotly_chart(styled_plot(fig), use_container_width=True)
    st.caption(
        "Plus la barre est rouge a droite, plus on a de clients silencieux : candidats au churn."
    )

with col_r:
    st.markdown("##### Distribution du panier moyen")
    panier = run_query("""
        SELECT avg_basket
        FROM mv_customer_features
        WHERE avg_basket < 1000
    """)
    fig = px.histogram(
        panier,
        x="avg_basket",
        nbins=40,
        color_discrete_sequence=[PRIMARY],
    )
    fig.update_layout(xaxis_title="Panier moyen (R$)", yaxis_title="")
    fig.update_traces(marker_line_width=0)
    st.plotly_chart(styled_plot(fig), use_container_width=True)
    st.caption(
        "Tronque a 1000 R$ pour la lisibilite. Quelques outliers depassent 4000 R$."
    )

st.markdown("##### Distribution de la frequence d'achat")
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
    color_discrete_sequence=[PRIMARY],
    text="nb_clients",
)
fig.update_traces(
    texttemplate="%{text:,d}".replace(",", " "),
    textposition="outside",
)
fig.update_layout(xaxis_title="Nombre de commandes", yaxis_title="")
st.plotly_chart(styled_plot(fig, height=260), use_container_width=True)
st.caption(
    "97% des clients n'ont commande qu'une fois. C'est le defi principal pour predire le churn sur ce dataset."
)

# ---------------------------------------------------------------------------
# Section 2 : Satisfaction
# ---------------------------------------------------------------------------

st.header("Satisfaction client")

col_l, col_r = st.columns(2)

with col_l:
    st.markdown("##### Repartition des notes moyennes")
    scores = run_query("""
        SELECT
            ROUND(avg_review_score)::INT AS note,
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
        color="note",
        color_continuous_scale=[(0.0, DANGER), (0.5, WARNING), (1.0, SUCCESS)],
        text="nb_clients",
    )
    fig.update_traces(
        texttemplate="%{text:,d}".replace(",", " "),
        textposition="outside",
    )
    fig.update_layout(xaxis_title="Note moyenne arrondie", yaxis_title="")
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(styled_plot(fig), use_container_width=True)

with col_r:
    st.markdown("##### Pourcentage de reviews negatives")
    neg = run_query("""
        SELECT pct_negative_reviews
        FROM mv_customer_features
        WHERE pct_negative_reviews IS NOT NULL
    """)
    fig = px.histogram(
        neg,
        x="pct_negative_reviews",
        nbins=20,
        color_discrete_sequence=[DANGER],
    )
    fig.update_layout(xaxis_title="% de reviews <= 2", yaxis_title="")
    fig.update_traces(marker_line_width=0)
    st.plotly_chart(styled_plot(fig), use_container_width=True)
    st.caption(
        "La majorite est a 0% (aucune review negative) mais un pic a 100% revele des clients deja braques."
    )

# ---------------------------------------------------------------------------
# Section 3 : Clients a risque
# ---------------------------------------------------------------------------

st.header("Clients a risque de churn")

st.markdown(
    """
    <div class="alert-box">
        <div class="alert-box-title">Definition retenue</div>
        Clients silencieux depuis <b>plus de 6 mois</b> ET ayant depense <b>plus de 200 R$</b>.
        Ce sont des clients qui ont eu de la valeur et qu'on est en train de perdre.
    </div>
    """,
    unsafe_allow_html=True,
)

risk_kpis = run_query("""
    SELECT
        COUNT(*) AS nb_a_risque,
        ROUND(SUM(total_spent), 0) AS revenue_perdu,
        ROUND(AVG(recency_days), 0) AS recence_moyenne,
        (SELECT ROUND(SUM(total_spent), 0) FROM mv_customer_features) AS revenue_total_global
    FROM mv_customer_features
    WHERE recency_days > 180
      AND total_spent > 200
""").iloc[0]

pct_revenue = risk_kpis.revenue_perdu / risk_kpis.revenue_total_global * 100

c1, c2, c3 = st.columns(3)
with c1:
    st.metric(
        "Clients identifies a risque",
        f"{int(risk_kpis.nb_a_risque):,}".replace(",", " "),
        delta=f"{risk_kpis.nb_a_risque / kpis.nb_clients * 100:.1f} % de la base",
        delta_color="off",
    )
with c2:
    st.metric(
        "Revenue cumule du groupe",
        f"{risk_kpis.revenue_perdu / 1_000_000:.2f} M R$",
        delta=f"{pct_revenue:.0f} % du CA total",
        delta_color="off",
    )
with c3:
    st.metric(
        "Recence moyenne du groupe",
        f"{int(risk_kpis.recence_moyenne)} jours",
    )

st.markdown("##### Top 20 clients a risque par valeur economique")
top_risk = run_query("""
    SELECT
        customer_unique_id AS "ID client",
        recency_days AS "Recence (j)",
        frequency AS "Commandes",
        total_spent AS "Depense totale (R$)",
        avg_review_score AS "Note moyenne",
        pct_negative_reviews AS "% reviews neg"
    FROM mv_customer_features
    WHERE recency_days > 180
      AND total_spent > 200
    ORDER BY total_spent DESC
    LIMIT 20
""")
st.dataframe(
    top_risk,
    use_container_width=True,
    hide_index=True,
    column_config={
        "Depense totale (R$)": st.column_config.NumberColumn(format="%.2f R$"),
        "Recence (j)": st.column_config.NumberColumn(format="%d j"),
        "Note moyenne": st.column_config.NumberColumn(format="%.2f"),
        "% reviews neg": st.column_config.NumberColumn(format="%.1f %%"),
    },
)
st.caption(
    "Liste a transmettre au marketing pour des actions de retention ciblees (relance, code promo, sondage)."
)

# ---------------------------------------------------------------------------
# Section 4 : Geographie
# ---------------------------------------------------------------------------

st.header("Repartition geographique")

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
    st.markdown("##### Top 10 etats par volume de clients")
    fig = px.bar(
        geo,
        x="state",
        y="nb_clients",
        color_discrete_sequence=[PRIMARY],
        text="nb_clients",
    )
    fig.update_traces(
        texttemplate="%{text:,d}".replace(",", " "),
        textposition="outside",
    )
    fig.update_layout(xaxis_title="", yaxis_title="")
    st.plotly_chart(styled_plot(fig), use_container_width=True)

with col_r:
    st.markdown("##### Depense moyenne par etat (top 10)")
    geo_sorted = geo.sort_values("panier_moyen", ascending=False)
    fig = px.bar(
        geo_sorted,
        x="state",
        y="panier_moyen",
        color="panier_moyen",
        color_continuous_scale=[(0.0, "#cfd8e3"), (1.0, PRIMARY)],
        text="panier_moyen",
    )
    fig.update_traces(
        texttemplate="%{text:.0f}",
        textposition="outside",
    )
    fig.update_layout(xaxis_title="", yaxis_title="R$")
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(styled_plot(fig), use_container_width=True)

st.caption(
    "Sao Paulo (SP) concentre l'essentiel de la base. "
    "Les etats moins peuples ont parfois des paniers moyens plus eleves (produits importes plus chers ?)."
)

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

st.markdown(
    """
    <div style="margin-top: 3rem; padding-top: 1rem; border-top: 1px solid #e5e7eb;
                color: #9ca3af; font-size: 0.8rem; text-align: center;">
        Source : vue materialisee <code>mv_customer_features</code>
        - 93 358 clients - dataset Olist 2016-2018 - cache Streamlit 5 min
    </div>
    """,
    unsafe_allow_html=True,
)
