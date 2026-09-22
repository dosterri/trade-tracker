-- Trade Tracker – Grundschema (Etappe 1)
-- Ausführen im Supabase-Dashboard: SQL Editor → New query → einfügen → Run.
-- Das Skript ist wiederholbar (idempotent).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Positionen
-- ---------------------------------------------------------------------------
create table if not exists public.positions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  asset_class     text not null check (asset_class in ('stock','etf','derivative','crypto')),
  name            text not null check (char_length(name) between 1 and 200),
  isin            text check (isin is null or isin ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'),
  symbol          text,
  currency        text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  price_source    text not null default 'manual'
                  check (price_source in ('ls','onvista','coingecko','manual')),
  source_ref      text,
  manual_price    numeric check (manual_price is null or manual_price >= 0),
  manual_price_at timestamptz,
  stop_loss       numeric,
  take_profit     numeric,
  derivative_type text check (derivative_type is null or derivative_type in
                  ('call','put','koLong','koShort','factorLong','factorShort','other')),
  underlying      text,
  strike          numeric,
  barrier         numeric,
  expiry          date,
  ratio           numeric check (ratio is null or ratio > 0),
  issuer          text,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists positions_user_idx on public.positions (user_id);

-- ---------------------------------------------------------------------------
-- Transaktionen (Kauf/Verkauf) – Basis der FIFO-Berechnung
-- ---------------------------------------------------------------------------
create table if not exists public.transactions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  position_id  uuid not null references public.positions (id) on delete cascade,
  side         text not null check (side in ('buy','sell')),
  quantity     numeric not null check (quantity > 0),
  price        numeric not null check (price >= 0),
  fees         numeric not null default 0 check (fees >= 0),
  taxes        numeric not null default 0,
  fx_rate      numeric not null default 1 check (fx_rate > 0),
  executed_at  timestamptz not null,
  created_at   timestamptz not null default now()
);

create index if not exists transactions_position_idx
  on public.transactions (position_id, executed_at);
create index if not exists transactions_user_idx on public.transactions (user_id);

-- ---------------------------------------------------------------------------
-- Kurs-Snapshots (Sparkline, später Basis für Alerts)
-- ---------------------------------------------------------------------------
create table if not exists public.price_snapshots (
  id           bigint generated always as identity primary key,
  user_id      uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  position_id  uuid not null references public.positions (id) on delete cascade,
  price        numeric not null check (price >= 0),
  currency     text not null check (currency ~ '^[A-Z]{3}$'),
  source       text not null,
  at           timestamptz not null default now()
);

create index if not exists price_snapshots_position_idx
  on public.price_snapshots (position_id, at desc);
create index if not exists price_snapshots_user_idx on public.price_snapshots (user_id);

-- updated_at automatisch pflegen
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists positions_touch on public.positions;
create trigger positions_touch before update on public.positions
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security: jede Zeile gehört genau einem Nutzer.
-- ---------------------------------------------------------------------------
alter table public.positions       enable row level security;
alter table public.transactions    enable row level security;
alter table public.price_snapshots enable row level security;

-- Anonyme Zugriffe grundsätzlich entziehen (RLS schützt zusätzlich).
revoke all on public.positions, public.transactions, public.price_snapshots from anon;
grant select, insert, update, delete on public.positions, public.transactions
  to authenticated;
grant select, insert, delete on public.price_snapshots to authenticated;

drop policy if exists positions_own on public.positions;
create policy positions_own on public.positions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Transaktionen/Snapshots nur zu eigenen Positionen.
drop policy if exists transactions_own on public.transactions;
create policy transactions_own on public.transactions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.positions p
                where p.id = position_id and p.user_id = (select auth.uid()))
  );

drop policy if exists snapshots_own on public.price_snapshots;
create policy snapshots_own on public.price_snapshots
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.positions p
                where p.id = position_id and p.user_id = (select auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- Keep-alive für den Gratis-Tarif: vom GitHub-Workflow täglich aufgerufen.
-- Gibt keine Nutzerdaten preis.
-- ---------------------------------------------------------------------------
create or replace function public.keepalive() returns text
language sql stable set search_path = '' as $$ select 'ok'::text $$;
grant execute on function public.keepalive() to anon, authenticated;
