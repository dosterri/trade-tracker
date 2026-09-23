# Trade Tracker

Persönlicher Trade- & Portfolio-Tracker für iOS und Windows (Flutter).
Aktien, ETFs, Derivate (Optionsscheine, Knock-outs, Faktor) und Krypto –
Lifecycle Kauf → Verkauf, FIFO-PnL in EUR, Trade-Cards mit Sparkline.

> Keine Anlageberatung. Die App dokumentiert nur eigene Trades.

## Etappen

| Etappe | Inhalt | Status |
|---|---|---|
| 1 – MVP | Manuelle Erfassung, FIFO, realisierte/unrealisierte PnL, EUR-Umrechnung, Kurse (LS/onvista/CoinGecko/EZB), Cards + Sparkline, Dark Mode, Supabase + RLS | ✅ |
| 2 – Alerts | Kursabfrage im Backend (pg_cron → Edge Function), Telegram + ntfy, Schwellen/SL/TP, Tagesübersicht, Wächter | ✅ |
| 3 – Import & Analytics | Trade-Republic-PDF-Import (in der App), Auswertungen nach Anlageklasse, Haltedauer, Trefferquote | ✅ |

## Aufbau

```
lib/core/      reine Logik (FIFO, FX, Bewertung, Formatierung) – ohne Flutter, getestet
lib/data/      Kursquellen (LS, onvista, CoinGecko, Frankfurter) + Supabase-Repository
lib/state/     AppState (ChangeNotifier)
lib/ui/        Oberfläche
supabase/migrations/  SQL (Tabellen, Row Level Security, Zeitplan)
supabase/functions/   Edge Functions (Deno/TypeScript): check-prices, send-test
test/          Unit- und Widget-Tests
tool/          live_check.dart – prüft, ob die Kursquellen erreichbar sind
```

## Geheimnisse

* `env/local.json` (lokal) und GitHub Secrets (CI) – **nie** ins Repo (`.gitignore`).
* In der App steckt nur der **Publishable/anon Key**. Er ist öffentlich gedacht;
  die Daten schützt Row Level Security (`user_id = auth.uid()`).
* Der `service_role`/`secret` Key wird in Etappe 1 nicht verwendet und gehört
  nie in die App oder ins Repo.

## Lokal starten (Windows)

```bash
flutter pub get
flutter run -d windows --dart-define-from-file=env/local.json
```

Release-Build: `flutter build windows --release --dart-define-from-file=env/local.json`
→ `build\windows\x64\runner\Release\trade_tracker.exe` (ganzen Ordner behalten).

Tests: `flutter test` · Analyse: `flutter analyze` · Kursquellen: `dart run tool/live_check.dart`

Backend (Deno):
`deno check supabase/functions/*/index.ts` · `deno test --allow-net supabase/functions/_shared/shared_test.ts`

## GitHub Actions

* **CI** (jeder Push): `flutter analyze` + `flutter test` auf Linux.
* **Build** (manuell: Actions → Build → Run workflow, oder Tag `v*`):
  unsignierte iOS-IPA (Sideloadly) und Windows-Build als Artifacts.
  Bei Fehlern steht eine kompakte Übersicht in der Job-Zusammenfassung.
* **Supabase Keep-alive** (täglich): verhindert das Pausieren im Gratis-Tarif.

Benötigte Repository-Secrets: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
optional `COINGECKO_DEMO_KEY`.

## Backend (Etappe 2)

`check-prices` holt mehrmals täglich Kurse (Zeitplan über pg_cron + pg_net),
schreibt Snapshots und verschickt Meldungen über Telegram und/oder ntfy.

* Function-Secrets: `TELEGRAM_BOT_TOKEN`, `CRON_SECRET`, optional `COINGECKO_DEMO_KEY`.
  `SUPABASE_URL` und `SUPABASE_SERVICE_ROLE_KEY` setzt Supabase selbst.
* Schwellen: je Position „Meldung ab Gewinn/Verlust %“ sowie Stop-Loss und
  Take-Profit. Jede Meldung kommt einmal und erst wieder, wenn die Schwelle
  zwischendurch unterschritten wurde (`alert_state`).
* Ruhezeiten und „Beträge mitschicken“ stellst du in der App ein.
* `backend_runs` protokolliert jeden Lauf; der Keep-alive-Workflow schlägt Alarm,
  wenn länger als 26 Stunden kein Lauf stattgefunden hat.

Die FIFO-Logik existiert doppelt (Dart in `lib/core/fifo.dart`, TypeScript in
`supabase/functions/_shared/fifo.ts`). Beide Seiten haben dieselben Testfälle –
bei Änderungen bitte beides anpassen.

## PDF-Import (Etappe 3)

* Läuft vollständig auf dem Gerät: `pdfrx` liest den Text, `lib/core/tr_parser.dart`
  wertet ihn aus. Die PDFs werden nicht hochgeladen, gespeichert werden nur die
  erkannten Buchungen.
* Erkannt werden Wertpapierabrechnungen (Kauf/Verkauf) mit ISIN, Stückzahl, Kurs,
  Gebühren, Steuern und Zeitpunkt. Kosteninformationen und Dividenden werden
  erkannt, aber nicht gebucht.
* Doppelte Importe verhindert `transactions.external_ref`
  (`tr:<Ausführungs-ID>:<Seite>:<ISIN>`, je Nutzer eindeutig).
* Je nach Textextraktion stehen Beschriftung und Wert in einer Zeile oder
  untereinander – der Parser normalisiert beides. Beide Varianten sind als
  Testdaten in `test/fixtures/` hinterlegt (anonymisiert).
* Ein Verkauf ohne passende Position wird abgelehnt, sonst entstünde ein
  Bestand unter null.

Zum Prüfen einer einzelnen Datei:
`dart run tool/pdf_probe.dart "C:\Pfad\zur\Abrechnung.pdf"`

## Kursquellen & Grenzen

| Asset | Quelle | Hinweis |
|---|---|---|
| Aktien/ETFs | Lang & Schwarz Exchange | inoffizielle Website-Schnittstelle, Mid-Kurs |
| Derivate | onvista | inoffiziell, Geldkurs (Bid), kein Verlauf → eigene Snapshots |
| Krypto | CoinGecko | ohne Key begrenzt; Demo-Key optional |
| FX | EZB via Frankfurter | einmal täglich aktualisiert |
| alles | manuell | Fallback, wenn eine Quelle ausfällt |

Stop-Loss/Take-Profit werden als „Kurs erreicht“ erkannt – ob der Broker
tatsächlich ausgeführt hat, kann die App nicht wissen.
