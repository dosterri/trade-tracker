-- Trade Tracker – Etappe 2: Benachrichtigungen & Alarme
-- Ausführen im Supabase-Dashboard: SQL Editor → New query → einfügen → Run.
-- Wiederholbar (idempotent).

-- ---------------------------------------------------------------------------
-- Alarm-Schwellen je Position
-- ---------------------------------------------------------------------------
alter table public.positions
  add column if not exists alert_up_pct   numeric check (alert_up_pct is null or alert_up_pct > 0),
  add column if not exists alert_down_pct numeric check (alert_down_pct is null or alert_down_pct > 0),
  add column if not exists alerts_enabled boolean not null default true;

comment on column public.positions.alert_up_pct is
  'Meldung, wenn der unrealisierte Gewinn diesen Prozentwert erreicht (z. B. 10).';
comment on column public.positions.alert_down_pct is
  'Meldung, wenn der unrealisierte Verlust diesen Prozentwert erreicht (z. B. 5).';

-- ---------------------------------------------------------------------------
-- Zustellwege je Nutzer
-- ---------------------------------------------------------------------------
create table if not exists public.notification_settings (
  user_id           uuid primary key default auth.uid()
                    references auth.users (id) on delete cascade,
  alerts_enabled    boolean not null default true,
  telegram_enabled  boolean not null default false,
  telegram_chat_id  text,
  ntfy_enabled      boolean not null default false,
  ntfy_topic        text,
  ntfy_server       text not null default 'https://ntfy.sh',
  include_amounts   boolean not null default true,
  daily_snapshot    boolean not null default true,
  quiet_from        smallint not null default 22 check (quiet_from between 0 and 23),
  quiet_to          smallint not null default 7  check (quiet_to between 0 and 23),
  timezone          text not null default 'Europe/Berlin',
  updated_at        timestamptz not null default now()
);

comment on table public.notification_settings is
  'Ein Datensatz je Nutzer. Das Telegram-Bot-Token liegt NICHT hier, sondern '
  'als Secret der Edge Function.';

-- ---------------------------------------------------------------------------
-- Alarm-Zustand (verhindert Dauerfeuer) und Verlauf
-- ---------------------------------------------------------------------------
create table if not exists public.alert_state (
  position_id uuid not null references public.positions (id) on delete cascade,
  kind        text not null check (kind in ('up','down','stop_loss','take_profit')),
  user_id     uuid not null default auth.uid()
              references auth.users (id) on delete cascade,
  active      boolean not null default false,
  last_sent   timestamptz,
  primary key (position_id, kind)
);

create table if not exists public.alert_events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid()
              references auth.users (id) on delete cascade,
  position_id uuid references public.positions (id) on delete cascade,
  kind        text not null,
  message     text not null,
  price       numeric,
  pct         numeric,
  delivered   text[] not null default '{}',
  at          timestamptz not null default now()
);

create index if not exists alert_events_user_idx on public.alert_events (user_id, at desc);

-- ---------------------------------------------------------------------------
-- Protokoll der Hintergrundläufe (Watchdog: läuft der Scheduler noch?)
-- ---------------------------------------------------------------------------
create table if not exists public.backend_runs (
  id        bigint generated always as identity primary key,
  kind      text not null,
  checked   int  not null default 0,
  alerts    int  not null default 0,
  errors    text[] not null default '{}',
  at        timestamptz not null default now()
);

create index if not exists backend_runs_at_idx on public.backend_runs (at desc);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.notification_settings enable row level security;
alter table public.alert_state           enable row level security;
alter table public.alert_events          enable row level security;
alter table public.backend_runs          enable row level security;

revoke all on public.notification_settings, public.alert_state,
  public.alert_events, public.backend_runs from anon;
grant select, insert, update, delete on public.notification_settings to authenticated;
grant select on public.alert_state, public.alert_events to authenticated;
grant delete on public.alert_events to authenticated;
grant select on public.backend_runs to authenticated;

drop policy if exists settings_own on public.notification_settings;
create policy settings_own on public.notification_settings
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists alert_state_own on public.alert_state;
create policy alert_state_own on public.alert_state
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists alert_events_own on public.alert_events;
create policy alert_events_own on public.alert_events
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Läufe darf jeder Angemeldete lesen (enthalten keine Nutzerdaten).
drop policy if exists backend_runs_read on public.backend_runs;
create policy backend_runs_read on public.backend_runs
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Watchdog: Wann lief der Scheduler zuletzt? (vom GitHub-Workflow geprüft)
-- ---------------------------------------------------------------------------
create or replace function public.last_backend_run()
returns table (kind text, at timestamptz, minutes_ago numeric)
language sql stable security definer set search_path = '' as $$
  select r.kind, r.at, extract(epoch from (now() - r.at)) / 60
  from public.backend_runs r
  order by r.at desc
  limit 1
$$;

grant execute on function public.last_backend_run() to anon, authenticated;
