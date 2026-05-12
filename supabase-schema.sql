-- ============================================================
-- KUBE DESIGN — Service Produit Logiciel
-- Schéma Supabase complet
-- ============================================================

-- Extensions
create extension if not exists "uuid-ossp";

-- ============================================================
-- TABLE : imports
-- Un enregistrement par fichier SODA importé
-- ============================================================
create table if not exists public.imports (
  id            uuid primary key default uuid_generate_v4(),
  imported_at   timestamptz not null default now(),
  file_name     text not null,
  row_count     int not null default 0,
  imported_by   text,                        -- email utilisateur si auth activée
  notes         text
);

create index if not exists imports_imported_at_idx on public.imports (imported_at desc);

-- ============================================================
-- TABLE : soda_rows
-- Lignes brutes du fichier SODA, liées à un import
-- ============================================================
create table if not exists public.soda_rows (
  id              bigserial primary key,
  import_id       uuid not null references public.imports(id) on delete cascade,
  type            text,
  marketing_name  text,
  sku             text,
  statut          text,
  emplacement     text,
  expediteur      text,
  enseigne        text,
  magasin         text,
  mobilier        text,
  livraison       date,
  imei            text,
  sn              text,
  planning        text,
  commentaire     text,
  gamme           text,
  created_at      timestamptz not null default now()
);

create index if not exists soda_rows_import_id_idx  on public.soda_rows (import_id);
create index if not exists soda_rows_statut_idx     on public.soda_rows (statut);
create index if not exists soda_rows_emplacement_idx on public.soda_rows (emplacement);
create index if not exists soda_rows_marketing_name_idx on public.soda_rows (marketing_name);
create index if not exists soda_rows_livraison_idx  on public.soda_rows (livraison);

-- ============================================================
-- TABLE : kpi_snapshots
-- KPI calculés et stockés à chaque import
-- ============================================================
create table if not exists public.kpi_snapshots (
  id              uuid primary key default uuid_generate_v4(),
  import_id       uuid not null references public.imports(id) on delete cascade,
  snapshot_at     timestamptz not null default now(),
  stock_physique  int not null default 0,
  stock_kube      int not null default 0,   -- disponible
  standby         int not null default 0,
  livraisons      int not null default 0,   -- entrées prestataires
  sorties         int not null default 0,   -- sorties Kube → magasin
  projet          int not null default 0,
  hs              int not null default 0,
  alert_low       int not null default 0,
  alert_critical  int not null default 0,
  alert_rupture   int not null default 0,
  anomalies       int not null default 0,
  taux_dispo      numeric(5,2)              -- stock_kube / stock_physique * 100
);

create index if not exists kpi_snapshots_import_id_idx  on public.kpi_snapshots (import_id);
create index if not exists kpi_snapshots_snapshot_at_idx on public.kpi_snapshots (snapshot_at desc);

-- ============================================================
-- TABLE : sku_stats
-- Statistiques par MARKETING_NAME calculées à l'import
-- ============================================================
create table if not exists public.sku_stats (
  id              bigserial primary key,
  import_id       uuid not null references public.imports(id) on delete cascade,
  marketing_name  text not null,
  gamme           text,
  qty_kube        int not null default 0,
  qty_standby     int not null default 0,
  qty_total       int not null default 0,
  alert_level     text,    -- 'ok' | 'low' | 'critical' | 'rupture'
  is_factice      boolean not null default false
);

create index if not exists sku_stats_import_id_idx      on public.sku_stats (import_id);
create index if not exists sku_stats_marketing_name_idx on public.sku_stats (marketing_name);
create index if not exists sku_stats_alert_level_idx    on public.sku_stats (alert_level);

-- ============================================================
-- TABLE : anomalies
-- Anomalies détectées à chaque import
-- ============================================================
create table if not exists public.anomalies (
  id              bigserial primary key,
  import_id       uuid not null references public.imports(id) on delete cascade,
  anomaly_type    text not null,
  sku             text,
  imei            text,
  sn              text,
  statut          text,
  emplacement     text,
  detail          text,
  dismissed       boolean not null default false,
  created_at      timestamptz not null default now()
);

create index if not exists anomalies_import_id_idx on public.anomalies (import_id);
create index if not exists anomalies_type_idx      on public.anomalies (anomaly_type);

-- ============================================================
-- TABLE : import_logs
-- Journal des opérations pour audit
-- ============================================================
create table if not exists public.import_logs (
  id          bigserial primary key,
  import_id   uuid references public.imports(id) on delete set null,
  event       text not null,   -- 'import_start' | 'import_success' | 'import_error' | 'export_generated'
  detail      text,
  user_agent  text,
  created_at  timestamptz not null default now()
);

create index if not exists import_logs_import_id_idx on public.import_logs (import_id);
create index if not exists import_logs_created_at_idx on public.import_logs (created_at desc);

-- ============================================================
-- VUE : v_kpi_history
-- Évolution des KPI dans le temps — pour graphiques tendance
-- ============================================================
create or replace view public.v_kpi_history as
select
  k.snapshot_at,
  i.file_name,
  k.stock_physique,
  k.stock_kube,
  k.standby,
  k.livraisons,
  k.sorties,
  k.projet,
  k.hs,
  k.alert_low,
  k.alert_critical,
  k.alert_rupture,
  k.taux_dispo
from public.kpi_snapshots k
join public.imports i on i.id = k.import_id
order by k.snapshot_at desc;

-- ============================================================
-- VUE : v_stock_tension
-- Produits en tension sur le dernier import
-- ============================================================
create or replace view public.v_stock_tension as
select
  s.marketing_name,
  s.gamme,
  s.qty_kube,
  s.qty_standby,
  s.qty_total,
  s.alert_level,
  i.imported_at
from public.sku_stats s
join public.imports i on i.id = s.import_id
where s.alert_level in ('critical', 'rupture')
  and i.id = (select id from public.imports order by imported_at desc limit 1)
order by s.qty_kube asc, s.marketing_name;

-- ============================================================
-- RLS (Row Level Security) — activer si authentification
-- ============================================================
-- alter table public.imports        enable row level security;
-- alter table public.soda_rows      enable row level security;
-- alter table public.kpi_snapshots  enable row level security;
-- alter table public.sku_stats      enable row level security;
-- alter table public.anomalies      enable row level security;
-- alter table public.import_logs    enable row level security;

-- Exemple de politique lecture seule pour utilisateurs authentifiés :
-- create policy "Authenticated read" on public.imports
--   for select to authenticated using (true);

-- ============================================================
-- COLONNES STORAGE — ajout sur la table imports
-- ============================================================
alter table public.imports add column if not exists file_path         text;
alter table public.imports add column if not exists file_url          text;
alter table public.imports add column if not exists original_filename text;
alter table public.imports add column if not exists last_opened_at    timestamptz;
alter table public.imports add column if not exists is_last_opened    boolean not null default false;

create index if not exists imports_last_opened_idx on public.imports (is_last_opened) where is_last_opened = true;

-- ============================================================
-- SUPABASE STORAGE — bucket imports-files
-- ============================================================
-- Exécuter dans le SQL Editor de Supabase :
--
-- insert into storage.buckets (id, name, public)
-- values ('imports-files', 'imports-files', false)
-- on conflict (id) do nothing;
--
-- create policy "anon_upload"  on storage.objects for insert to anon
--   with check (bucket_id = 'imports-files');
-- create policy "anon_select"  on storage.objects for select to anon
--   using (bucket_id = 'imports-files');
-- create policy "anon_delete"  on storage.objects for delete to anon
--   using (bucket_id = 'imports-files');

-- ============================================================
-- FONCTION : insert_import_with_kpis
-- Insère un import + son snapshot KPI en une transaction
-- ============================================================
create or replace function public.insert_import_with_kpis(
  p_file_name     text,
  p_row_count     int,
  p_stock_physique int,
  p_stock_kube    int,
  p_standby       int,
  p_livraisons    int,
  p_sorties       int,
  p_projet        int,
  p_hs            int,
  p_alert_low     int,
  p_alert_critical int,
  p_alert_rupture int,
  p_anomalies     int
)
returns uuid
language plpgsql
as $$
declare
  v_import_id uuid;
  v_taux_dispo numeric(5,2);
begin
  insert into public.imports (file_name, row_count)
  values (p_file_name, p_row_count)
  returning id into v_import_id;

  v_taux_dispo := case
    when p_stock_physique > 0
    then round((p_stock_kube::numeric / p_stock_physique) * 100, 2)
    else null
  end;

  insert into public.kpi_snapshots (
    import_id, stock_physique, stock_kube, standby, livraisons,
    sorties, projet, hs, alert_low, alert_critical, alert_rupture,
    anomalies, taux_dispo
  ) values (
    v_import_id, p_stock_physique, p_stock_kube, p_standby, p_livraisons,
    p_sorties, p_projet, p_hs, p_alert_low, p_alert_critical, p_alert_rupture,
    p_anomalies, v_taux_dispo
  );

  return v_import_id;
end;
$$;
