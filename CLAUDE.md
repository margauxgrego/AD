# Instructions Claude Code

## Règle principale
Réponses les plus courtes possible. Minimum de tokens. Pas d'explication non demandée, pas de résumé en fin de réponse.

## Projet
Application HTML standalone de gestion de stock Samsung (Kube Design).
Fichier principal : `gestion-stock-service-produit.html`

## Export reporting (STOCK KUBE DDMMYYYY.xls)
- Feuille 1 : **TCD** — pivot MARKETING_NAME × STATUT, filtre TYPE = RDU ou LDU uniquement
- Feuille 2 : **BDD** — toutes les lignes, 17 colonnes SODA (sans ID), header bleu #0070C0

## Règles métier
- ACC sans IMEI/SN = vrais produits (pas des factices)
- CDM IDF/PROVINCE à KUBE DESIGN = stock disponible
