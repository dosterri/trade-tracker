-- Trade Tracker – Zeitplan für die Kursabfrage (Etappe 2)
--
-- VOR dem Ausführen die beiden Platzhalter ersetzen:
--   PROJEKT_REF  → z. B. xkwnkzrpxtoiuakqwfpx  (steht in deiner Supabase-URL)
--   CRON_SECRET  → dasselbe Geheimnis wie im Function-Secret CRON_SECRET
--
-- Danach im SQL Editor ausführen. Wiederholtes Ausführen ist erlaubt,
-- bestehende Jobs werden vorher entfernt.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Alte Jobs entfernen (Fehler ignorieren, falls noch keine existieren)
do $$
declare j text;
begin
  foreach j in array array['tt-check-weekday','tt-check-weekend','tt-daily-summer','tt-daily-winter']
  loop
    begin
      perform cron.unschedule(j);
    exception when others then null;
    end;
  end loop;
end $$;

-- Werktags stündlich (UTC). Die Funktion selbst prüft die lokale Handelszeit.
select cron.schedule(
  'tt-check-weekday',
  '0 6-21 * * 1-5',
  $job$
  select net.http_post(
    url     := 'https://PROJEKT_REF.supabase.co/functions/v1/check-prices?mode=check',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', 'CRON_SECRET'),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);

-- Am Wochenende alle 4 Stunden (nur Krypto liefert dann Kurse).
select cron.schedule(
  'tt-check-weekend',
  '0 */4 * * 6,0',
  $job$
  select net.http_post(
    url     := 'https://PROJEKT_REF.supabase.co/functions/v1/check-prices?mode=check',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', 'CRON_SECRET'),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);

-- Tagesübersicht: zwei Läufe wegen Sommer-/Winterzeit; die Funktion verschickt
-- nur den Lauf, der lokal 21 Uhr trifft.
select cron.schedule(
  'tt-daily-summer',
  '50 19 * * 1-5',
  $job$
  select net.http_post(
    url     := 'https://PROJEKT_REF.supabase.co/functions/v1/check-prices?mode=daily',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', 'CRON_SECRET'),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);

select cron.schedule(
  'tt-daily-winter',
  '50 20 * * 1-5',
  $job$
  select net.http_post(
    url     := 'https://PROJEKT_REF.supabase.co/functions/v1/check-prices?mode=daily',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-cron-secret', 'CRON_SECRET'),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);

-- Kontrolle: geplante Jobs anzeigen
select jobid, jobname, schedule, active from cron.job order by jobname;

-- Nützlich zur Fehlersuche (zeigt die letzten Aufrufe):
--   select * from cron.job_run_details order by start_time desc limit 20;
--   select * from public.backend_runs order by at desc limit 20;
