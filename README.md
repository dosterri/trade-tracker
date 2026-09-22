# Trade Tracker

Persönlicher Trade- & Portfolio-Tracker für iOS und Windows (Flutter).
Aktien, ETFs, Derivate (Optionsscheine, Knock-outs, Faktor) und Krypto –
Lifecycle Kauf → Verkauf, FIFO-PnL in EUR, Trade-Cards mit Sparkline.

> Keine Anlageberatung. Die App dokumentiert nur eigene Trades.

## Etappen

| Etappe | Inhalt | Status |
|---|---|---|
| 1 – MVP | Manuelle Erfassung, FIFO, realisierte/unrealisierte PnL, EUR-Umrechnung, Kurse (LS/onvista/CoinGecko/EZB), Cards + Sparkline, Dark Mode, Supabase + RLS | ✅ |
| 2 – Alerts | Kursabfrage im Backend (pg_cron → Edge Function), Telegram + ntfy, Schwellen/Targets/SL/TP, Tages-Snapshot | geplant |
| 3 – Import & Analytics | Trade-Republic-PDF-Import (in der App), Auswertungen nach Asset-Klasse, Haltedauer, Win/Loss | geplant |

## Aufbau

```
lib/core/      reine Logik (FIFO, FX, Bewertung, Formatierung) – ohne Flutter, getestet
lib/data/      Kursquellen (LS, onvista, CoinGecko, Frankfurter) + Supabase-Repository
lib/state/     AppState (ChangeNotifier)
lib/ui/        Oberfläche
supabase/      SQL-Migrationen (Tabellen, Row Level Security)
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

## GitHub Actions

* **CI** (jeder Push): `flutter analyze` + `flutter test` auf Linux.
* **Build** (manuell: Actions → Build → Run workflow, oder Tag `v*`):
  unsignierte iOS-IPA (Sideloadly) und Windows-Build als Artifacts.
  Bei Fehlern steht eine kompakte Übersicht in der Job-Zusammenfassung.
* **Supabase Keep-alive** (täglich): verhindert das Pausieren im Gratis-Tarif.

Benötigte Repository-Secrets: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
optional `COINGECKO_DEMO_KEY`.

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
