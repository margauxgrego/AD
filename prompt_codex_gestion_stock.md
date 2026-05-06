# Prompt Codex — Projet "Gestion de stock au service produit"

> À copier-coller dans Codex.

---

## 🎯 Contexte et objectif

Tu vas développer une **application web locale** (un seul fichier HTML autonome, pas de serveur, pas d'install) pour la **gestionnaire de stock du service produit chez Kube Design**.

Kube Design est **prestataire de service pour Samsung** : on ne vend rien, on installe les produits Samsung demandés (téléphones, tablettes, montres, accessoires…) en magasin (Boulanger, Fnac, Darty, Orange, etc.). On gère donc un stock de produits qui transitent par notre entrepôt avant d'aller en magasin.

Le WMS utilisé s'appelle **SODA** : il sait gérer les entrées/sorties et tracer chaque unité, mais **il ne sait pas calculer combien on a en stock à un instant T**. Il sait juste exporter un fichier xlsx/csv.

L'application s'appelle **"Gestion de stock au service produit"**. Elle est **complémentaire à SODA** : c'est un dashboard qui sert pour les **reportings hebdomadaires** et la **gestion de stock au quotidien**.

**Principe de fonctionnement :** un seul drag & drop du fichier exporté de SODA → tous les KPI, alertes et tableaux se calculent automatiquement. Aucune saisie manuelle. À chaque nouvel import, **tout est recalculé from scratch** (les données précédentes sont écrasées).

---

## 📁 Structure réelle de l'export SODA (à respecter strictement)

Le fichier exporté contient **1 feuille**, **18 colonnes**, et **~30 000 lignes**. Chaque ligne = 1 unité physique identifiée par un IMEI ou un SN. **Donc le stock par SKU = COUNT des lignes correspondantes, pas une somme d'une colonne quantité.**

| Colonne | Description / Notes |
|---|---|
| `ID` | Identifiant interne SODA, unique par ligne |
| `GAMME` | Famille produit. Valeurs : `S SERIES`, `Z SERIES`, `A SERIES`, `TAB`, `WATCH`, `BUDS`, `BOOK`, `ACC`, `DPOP`, `XCOVER`, `RING`. ⚠️ espaces parasites possibles → **trim obligatoire** |
| `PRODUIT` | Nom du produit (ex. `S25 ULTRA`, `BUDS 3 PRO`, `BOOK4 EDGE 16`) |
| `TYPE` | Type d'article (ex. `RDU` = real demo unit, `COVER`, `FACTICE`) |
| `COLORIS` | Couleur (ex. `GRIS`, `BLEU CLAIR`, `VIOLET`) |
| `MARKETING_NAME` | Nom commercial complet. **Peut varier pour un même SKU** (saisies différentes selon les opérateurs) — d'où la règle de normalisation ci-dessous |
| `SKU` | **Référence officielle constructeur** (ex. `SM-S921BZVDEUC`). **C'est la clé métier principale.** Cas particulier : la valeur `FACTICE` est utilisée pour des dizaines de produits différents — voir règle de désambiguïsation |
| `IMEI` | Identifiant unique téléphone (souvent vide pour les accessoires) |
| `SN` | Numéro de série (souvent identique à IMEI, parfois différent) |
| `STATUT` | Voir tableau de catégorisation ci-dessous. ⚠️ trim obligatoire (`STOCK KUBE ` avec espace existe) |
| `EMPLACEMENT` | Lieu physique. Trois valeurs uniquement : `KUBE DESIGN` (entrepôt), `LIVRAISON` (en transit), `MAGASIN` (déjà installé) |
| `EXPEDITEUR` | Qui a livré l'unité chez Kube. Top valeurs : `DHL`, `KUBE DESIGN`, `ICP`, `INOVSHOP`, `DMF`, `IMPACT`, `ATMOSPHERE`. ⚠️ trim |
| `LIVRAISON` | Date de réception chez Kube. ⚠️ **Souvent contient juste `" X"`** quand la date n'est pas connue → ce n'est PAS un signal "pas encore arrivé", c'est juste une donnée manquante. Traiter en best-effort, ne pas planter si non parseable |
| `ENSEIGNE` | Enseigne du magasin destinataire (`BOULANGER`, `FNAC`, `DARTY`, `ORANGE`, `BOUYGUES`, `SAMSUNG STORE`…). ⚠️ trim |
| `MAGASIN` | Nom/ville du magasin spécifique |
| `PLANNING` | Format libre : `"PRENOM(S) [CDM] Wxx ANNEE"`. Ex : `"TODOR CDM W09 2026"`, `"PIERRE / JORDAN W08 2026"`. Indique **quel technicien part installer le produit en magasin et quelle semaine ISO**. À parser |
| `MOBILIER` | Type de mobilier d'installation en magasin |
| `COMMENTAIRE` | Notes libres (ex. `GRADE B`, `GRADE C`) |

---

## 🧠 Règles métier (lecture obligatoire avant codage)

### Règle 1 — Catégorisation des unités

L'**EMPLACEMENT** indique où l'unité se trouve physiquement. Le **STATUT** indique son état comptable / logistique. Les deux se combinent ainsi :

| Catégorie applicative | Règle de filtre | Sens métier |
|---|---|---|
| **STOCK DISPO KUBE** | `STATUT = STOCK KUBE` ET `EMPLACEMENT = KUBE DESIGN` | Unités à nous, prêtes à partir en installation |
| **STOCK DISPO STANDBY** | `STATUT = STANDBY` ET `EMPLACEMENT = KUBE DESIGN` | Unités d'un prestataire externe stockées chez nous, prêtes à partir |
| **RÉSERVÉ PROJET** | `STATUT = PROJET` ET `EMPLACEMENT = KUBE DESIGN` | Physiquement dispo, mais réservé pour un projet précis — ne pas piocher dedans pour autre chose |
| **HS** | `STATUT = HS` | Présent dans nos stocks mais non utilisable (cassé, défaut) |
| **EN LIVRAISON ENTRANTE** | `STATUT = LIVRAISON` (et `EMPLACEMENT = LIVRAISON`) | En transit vers Kube, pas encore arrivé |
| **EN LIVRAISON SORTANTE CDM IDF** | `STATUT = CDM IDF` | Confié à un Chef De Maintenance Île-de-France pour acheminement vers magasin → **plus chez nous** |
| **EN LIVRAISON SORTANTE CDM PROVINCE** | `STATUT = CDM PROVINCE` | Idem, pour la province → **plus chez nous** |
| **INSTALLÉ EN MAGASIN** | `STATUT = MAGASIN` | Sorti, posé en magasin |
| **VOL** | `STATUT = VOL` | Sorti, perdu/volé |

### Règle 2 — Définition stricte du "stock disponible"

> **Stock disponible = `STATUT ∈ {STOCK KUBE, STANDBY}` ET `EMPLACEMENT = KUBE DESIGN`**

C'est **uniquement** sur ce périmètre que portent :
- le compteur principal "Stock total disponible"
- les alertes orange / rouge / rupture
- les calculs par SKU dans le tableau pivot

`PROJET`, `HS`, `CDM IDF`, `CDM PROVINCE`, `LIVRAISON` ne sont **pas** comptés dedans, mais sont affichés dans des KPI distincts.

### Règle 3 — Normalisation du nom produit par SKU

> *« Je voudrai que le logiciel nomme les produits en fonction du SKU, et il prendra le marketing_name de ce SKU le plus utilisé. »*

Pour chaque SKU unique :
1. Compter combien de fois chaque `MARKETING_NAME` apparaît
2. Garder le marketing_name **le plus fréquent** comme nom canonique du SKU
3. **Cas particulier `SKU = "FACTICE"`** (et tout SKU utilisé pour > 5 marketing_names différents) : la clé de regroupement devient `SKU + PRODUIT + COLORIS` au lieu de juste `SKU`. Sinon on regroupe à tort des Buds avec des Watch sous une même ligne.

### Règle 4 — Alertes de niveau de stock par SKU (seuils FIGÉS, non paramétrables)

Pour chaque SKU (regroupé selon Règle 3), calculer la quantité de stock disponible (Règle 2) :

| Quantité | Couleur | Libellé |
|---|---|---|
| `≥ 16` | 🟢 vert | OK |
| `5 ≤ qty ≤ 15` | 🟠 orange | Bas |
| `1 ≤ qty ≤ 4` | 🔴 rouge | Critique |
| `0` | ⚫ gris | Rupture |

**Ces seuils sont en dur dans le code, pas de panneau réglages, pas de variation par gamme.**

### Règle 5 — Nettoyage systématique à l'import

Sur **toutes les colonnes texte** :
- `.trim()` (espaces avant/après)
- Uppercase pour `STATUT`, `EMPLACEMENT`, `EXPEDITEUR`, `ENSEIGNE`, `GAMME`
- Remplacer `NaN` / `""` / `" "` par `null`
- `LIVRAISON` : tenter parse date FR (`DD/MM/YYYY`, `DD-MM-YYYY`, ou Excel serial), sinon `null` sans planter

### Règle 6 — Parsing du PLANNING

Regex suggérée : `^(.+?)\s+(?:CDM\s+)?W(\d{1,2})\s+(\d{4})$`
→ capture `(technicien, semaine ISO, année)`. Si ça ne matche pas, garder le texte brut.

Permet ensuite : "installations cette semaine", "top techniciens", filtrage par semaine.

### Règle 7 — Recalcul complet à chaque import

Chaque import écrase les données précédentes. Pas de fusion, pas de comparaison N vs N-1, pas d'historique.

---

## 📊 KPI à afficher (tous cliquables → drawer ou modale avec tableau filtré)

### Bandeau KPI principal (sticky en haut)

1. **📦 Stock total disponible** — count des unités `STOCK KUBE + STANDBY` à `KUBE DESIGN`. Cliquable → tableau filtré.
2. **🟢 SKU OK** — nombre de SKU avec qty ≥ 16
3. **🟠 SKU en alerte (Bas)** — nombre de SKU entre 5 et 15. Cliquable → liste triée par quantité croissante
4. **🔴 SKU en critique** — nombre de SKU entre 1 et 4. Cliquable → liste, **mise en avant visuelle forte** (cadre rouge, animation discrète de pulsation)
5. **⚫ SKU en rupture** — nombre de SKU à 0 mais qui apparaissent dans le fichier (donc qu'on a déjà eus)

### KPI secondaires

6. **🔒 Réservé projet** — count des unités `PROJET` à `KUBE DESIGN`. Cliquable.
7. **🔧 HS** — count des unités `HS`. Cliquable.
8. **🚚 En livraison entrante** — count `STATUT = LIVRAISON`. Cliquable → liste avec expéditeur.
9. **📤 En livraison sortante CDM** — count `STATUT ∈ {CDM IDF, CDM PROVINCE}`. Cliquable.
10. **🏪 Installées en magasin (mois en cours)** — count `STATUT = MAGASIN`. Cliquable.
11. **🤝 STANDBY par prestataire** — pie chart par EXPEDITEUR (sur les unités STANDBY uniquement).
12. **📅 Plannings semaine en cours** — installations prévues cette semaine ISO. Cliquable → tableau (technicien, magasin, enseigne, mobilier).
13. **👷 Top techniciens (mois)** — bar chart des installations par technicien.
14. **🏬 Top enseignes destinataires** — bar chart Boulanger / Fnac / Darty / etc.
15. **🗂️ Répartition par GAMME** — donut chart (S Series, Watch, Buds, ACC…) sur le stock dispo.
16. **❌ Anomalies** — count d'incohérences détectées. Cliquable → liste détaillée. Cas à signaler :
    - `STATUT = MAGASIN` mais `EMPLACEMENT ≠ MAGASIN`
    - `STATUT = STOCK KUBE` mais `EMPLACEMENT ≠ KUBE DESIGN`
    - `IMEI` ou `SN` dupliqué entre deux lignes actives (= deux unités physiques avec le même identifiant, impossible)
    - `SKU` vide ou null
    - `STATUT` ou `EMPLACEMENT` non reconnu (hors valeurs listées)

> Tous les KPI sont cliquables. Un clic ouvre un **drawer latéral** ou une **modale** avec le tableau filtré + bouton "Exporter en CSV".

---

## 🖥️ UX / Interface

### Écran d'import (initial)
- Plein écran, drag & drop xlsx/csv au centre, ou bouton "Parcourir".
- Message clair : "Glissez votre export SODA ici".
- Disparaît dès que le fichier est chargé, remplacé par le dashboard.

### Dashboard (après import)
- **Bandeau KPI sticky** en haut.
- **Onglets** sous les KPI :
  1. **Vue stock par SKU** — tableau pivot. Colonnes : `Nom canonique` (issu Règle 3), `SKU`, `Gamme`, `Qty Stock Kube`, `Qty Standby`, `Qty Total Dispo`, `Statut alerte` (pastille couleur). Tri sur chaque colonne, recherche, filtre par gamme.
  2. **Vue détail unitaire** — toutes les lignes du fichier. Recherche par SKU / IMEI / SN / Marketing_name / Magasin. Filtres multiples (gamme, statut, emplacement, enseigne).
  3. **Plannings** — tableau par semaine ISO avec technicien, magasin, enseigne, mobilier, SKU installé.
  4. **Anomalies** — tableau des incohérences détectées (Règle 16).
- **Recherche globale** dans la barre du haut (cherche dans SKU, IMEI, SN, Marketing_name, Magasin, simultanément).
- **Bouton "Nouvel import"** en haut à droite pour remplacer les données.
- **Indicateur** en haut à droite : nom du fichier importé + nombre de lignes + horodatage de l'import.

### Exports
Chaque tableau a un bouton **"Exporter CSV"** et **"Exporter Excel"**.

---

## 🛠️ Stack technique

- **Un seul fichier `gestion-stock-service-produit.html`** autonome. Doit fonctionner par double-clic, pas de serveur, pas de build.
- **Libs via CDN uniquement** :
  - [SheetJS](https://cdn.sheetjs.com/) pour lire xlsx/csv
  - [Chart.js](https://www.chartjs.org/) pour les graphes
- **Vanilla JS** (pas de React, pas de Vue). Si besoin de réactivité simple, Alpine.js via CDN accepté.
- **CSS custom** propre (pas de Tailwind — trop lourd pour un fichier unique sans build).
- **Style** : design sobre type ERP professionnel (inspiration e-Prelude / SAP). Police système (Segoe UI / -apple-system). Palette bleus/gris neutres + sémantique vert/orange/rouge/gris pour les alertes.
- **Responsive** : lisible plein écran et sur 13 pouces.
- **Performance** : 30 000 lignes doivent passer fluidement → pagination 100 lignes/page minimum, ou virtualisation de table.

---

## ✅ Critères d'acceptation

1. Drag & drop de l'export SODA → dashboard rempli en moins de 5 secondes.
2. Le compteur "Stock total disponible" correspond exactement au count de `STATUT ∈ {STOCK KUBE, STANDBY}` ET `EMPLACEMENT = KUBE DESIGN` (Règle 2).
3. `PROJET`, `HS`, `CDM IDF`, `CDM PROVINCE`, `LIVRAISON` ne sont **pas** comptés dans le stock dispo, mais apparaissent dans leurs KPI dédiés.
4. Les SKU avec qty entre 5 et 15 sont **orange**, entre 1 et 4 **rouges**, à 0 **gris**, ≥ 16 **verts**.
5. Tous les KPI sont cliquables et ouvrent une vue détaillée filtrée.
6. Le nom affiché pour chaque SKU est le `MARKETING_NAME` le plus fréquent (Règle 3), avec désambiguïsation pour les SKU génériques type `FACTICE`.
7. Les espaces parasites dans `STATUT`, `EXPEDITEUR`, `ENSEIGNE`, `GAMME` sont nettoyés (pas de doublon `STOCK KUBE` / `STOCK KUBE ` dans les listes).
8. Chaque vue est exportable en CSV.
9. Le total des lignes affichées toutes catégories confondues = nombre de lignes du fichier importé (rien n'est perdu, rien n'est dupliqué).
10. Page sans erreur console sur Chrome / Edge / Firefox récents.
11. La colonne `LIVRAISON` qui contient `" X"` est traitée comme une date manquante, **sans bloquer l'import**.

---

## ⚠️ Pièges à éviter (relire avant de coder)

- ❌ Ne **pas** sommer une colonne quantité — elle n'existe pas, chaque ligne = 1 unité.
- ❌ Ne **pas** considérer `LIVRAISON = " X"` comme "produit en transit". L'EMPLACEMENT seul détermine où le produit se trouve physiquement. La colonne LIVRAISON est une date (souvent manquante).
- ❌ Ne **pas** inclure `PROJET`, `HS`, `CDM IDF`, `CDM PROVINCE` dans le stock dispo — ils sont à part.
- ❌ Ne **pas** oublier `.trim()` partout — sinon les filtres et regroupements seront cassés en silence.
- ❌ Ne **pas** utiliser `MARKETING_NAME` comme clé de regroupement, **toujours `SKU`** (sauf désambiguïsation Règle 3).
- ❌ Ne **pas** prévoir de panneau de réglages pour les seuils — ils sont figés (5 et 15).
- ❌ Ne **pas** prévoir de comparaison N vs N-1 ni d'historique — chaque import écrase tout.

---

## 📦 Livrable attendu

Un seul fichier `gestion-stock-service-produit.html` que je peux double-cliquer pour ouvrir dans un navigateur, sans aucune installation.

Inclure un **jeu de données de démo** intégré (15-20 lignes représentatives couvrant tous les statuts) qui se charge si aucun fichier n'est importé, pour tester l'UI immédiatement.

Code commenté en français aux endroits clés (logique métier des règles 1-7).
