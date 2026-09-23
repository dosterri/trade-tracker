-- Trade Tracker – Etappe 3: PDF-Import
-- Ausführen im Supabase-Dashboard: SQL Editor → New query → einfügen → Run.

-- Kennzeichen der Quelle (z. B. "tr:<Ausführungs-ID>:sell:<ISIN>").
-- Verhindert, dass dieselbe Abrechnung zweimal importiert wird.
alter table public.transactions
  add column if not exists external_ref text;

create unique index if not exists transactions_external_ref_uidx
  on public.transactions (user_id, external_ref)
  where external_ref is not null;

comment on column public.transactions.external_ref is
  'Herkunft der Buchung beim Import; eindeutig je Nutzer.';

notify pgrst, 'reload schema';
