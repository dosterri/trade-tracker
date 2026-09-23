// Holt Kurse, speichert Snapshots und verschickt Alarme.
// Aufruf durch pg_cron (Header x-cron-secret) mit ?mode=check oder ?mode=daily.
//
// Secrets: TELEGRAM_BOT_TOKEN, CRON_SECRET, optional COINGECKO_DEMO_KEY.
// SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY stellt Supabase automatisch bereit.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { computeLedger, type Txn } from "../_shared/fifo.ts";
import { type PositionRow, fxRates, quoteFor } from "../_shared/quotes.ts";
import {
  eur,
  hourIn,
  inQuietHours,
  notify,
  type NotifySettings,
  pct,
  price as fmtPrice,
  weekdayIn,
} from "../_shared/notify.ts";

interface Position extends PositionRow {
  user_id: string;
  name: string;
  stop_loss: number | null;
  take_profit: number | null;
  alert_up_pct: number | null;
  alert_down_pct: number | null;
  alerts_enabled: boolean;
}

interface Settings extends NotifySettings {
  user_id: string;
  alerts_enabled: boolean;
  include_amounts: boolean;
  daily_snapshot: boolean;
  quiet_from: number;
  quiet_to: number;
  timezone: string;
}

const CONCURRENCY = 4;

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SB_SECRET_KEY")!,
  { auth: { persistSession: false } },
);

/** Handelszeitfenster: Krypto immer, alles andere Mo–Fr 08–23 Uhr lokal. */
function shouldFetch(p: Position, tz: string): boolean {
  if (p.asset_class === "crypto") return true;
  const h = hourIn(tz, new Date());
  return weekdayIn(tz) <= 5 && h >= 8 && h < 23;
}

async function inBatches<T>(items: T[], size: number, fn: (x: T) => Promise<void>) {
  for (let i = 0; i < items.length; i += size) {
    await Promise.all(items.slice(i, i + size).map(fn));
  }
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("unauthorized", { status: 401 });
  }

  const mode = new URL(req.url).searchParams.get("mode") === "daily" ? "daily" : "check";
  const errors: string[] = [];
  let checked = 0;
  let alertsSent = 0;

  try {
    let fx: Record<string, number> = { EUR: 1 };
    try {
      fx = await fxRates();
    } catch (e) {
      errors.push(`fx: ${e instanceof Error ? e.message : e}`);
    }

    const [{ data: positions }, { data: txns }, { data: settingsRows }, { data: states }] =
      await Promise.all([
        db.from("positions").select("*"),
        db.from("transactions").select("*"),
        db.from("notification_settings").select("*"),
        db.from("alert_state").select("*"),
      ]);

    const settingsByUser = new Map<string, Settings>(
      (settingsRows ?? []).map((s) => [s.user_id, s as Settings]),
    );
    const txnsByPosition = new Map<string, Txn[]>();
    for (const t of (txns ?? []) as (Txn & { position_id: string })[]) {
      const list = txnsByPosition.get(t.position_id) ?? [];
      list.push(t);
      txnsByPosition.set(t.position_id, list);
    }
    const stateKey = (positionId: string, kind: string) => `${positionId}|${kind}`;
    const stateMap = new Map<string, { active: boolean }>(
      (states ?? []).map((s) => [stateKey(s.position_id, s.kind), { active: s.active }]),
    );

    const snapshots: Record<string, unknown>[] = [];
    const events: Record<string, unknown>[] = [];
    const stateUpserts: Record<string, unknown>[] = [];
    // Tagesübersicht je Nutzer
    const daily = new Map<string, { lines: string[]; value: number; pnl: number }>();

    const coinKey = Deno.env.get("COINGECKO_DEMO_KEY") ?? "";

    await inBatches(((positions ?? []) as Position[]), CONCURRENCY, async (p) => {
      const settings = settingsByUser.get(p.user_id);
      const tz = settings?.timezone ?? "Europe/Berlin";
      const ledger = computeLedger(txnsByPosition.get(p.id) ?? []);
      if (ledger.openQty <= 1e-9) return;
      if (!shouldFetch(p, tz) && mode !== "daily") return;

      let quote;
      try {
        quote = await quoteFor(p, coinKey);
      } catch (e) {
        errors.push(`${p.name}: ${e instanceof Error ? e.message : e}`);
        return;
      }
      if (!quote) return;
      checked++;

      if (quote.source !== "manual") {
        snapshots.push({
          user_id: p.user_id,
          position_id: p.id,
          price: quote.price,
          currency: quote.currency,
          source: quote.source,
        });
      }

      const rate = fx[quote.currency.toUpperCase()];
      const valueEur = rate ? (ledger.openQty * quote.price) / rate : null;
      const pnlEur = valueEur === null ? null : valueEur - ledger.openCostEur;
      const ratio = pnlEur === null || ledger.openCostEur <= 0
        ? null
        : pnlEur / ledger.openCostEur;

      // --- Tagesübersicht sammeln
      if (mode === "daily" && settings?.daily_snapshot) {
        const d = daily.get(p.user_id) ?? { lines: [], value: 0, pnl: 0 };
        const amount = settings.include_amounts && pnlEur !== null
          ? `  ${eur(pnlEur)}`
          : "";
        d.lines.push(
          `• ${p.name}: ${fmtPrice(quote.price, quote.currency)}  ${
            ratio === null ? "–" : pct(ratio)
          }${amount}`,
        );
        d.value += valueEur ?? 0;
        d.pnl += pnlEur ?? 0;
        daily.set(p.user_id, d);
        return;
      }

      // --- Schwellen prüfen
      if (mode !== "check" || !settings || !settings.alerts_enabled || !p.alerts_enabled) {
        return;
      }
      const sameCcy = quote.currency === p.currency;
      const conditions: { kind: string; hit: boolean; title: string; body: string }[] = [
        {
          kind: "up",
          hit: p.alert_up_pct !== null && ratio !== null && ratio * 100 >= p.alert_up_pct,
          title: `📈 ${p.name} ${ratio === null ? "" : pct(ratio)}`,
          body: `Kurs ${fmtPrice(quote.price, quote.currency)}`,
        },
        {
          kind: "down",
          hit: p.alert_down_pct !== null && ratio !== null &&
            ratio * 100 <= -p.alert_down_pct,
          title: `📉 ${p.name} ${ratio === null ? "" : pct(ratio)}`,
          body: `Kurs ${fmtPrice(quote.price, quote.currency)}`,
        },
        {
          kind: "stop_loss",
          hit: sameCcy && p.stop_loss !== null && quote.price <= p.stop_loss,
          title: `🛑 Stop-Loss erreicht: ${p.name}`,
          body: `Kurs ${fmtPrice(quote.price, quote.currency)} ≤ ${
            fmtPrice(p.stop_loss ?? 0, p.currency)
          }`,
        },
        {
          kind: "take_profit",
          hit: sameCcy && p.take_profit !== null && quote.price >= p.take_profit,
          title: `🎯 Take-Profit erreicht: ${p.name}`,
          body: `Kurs ${fmtPrice(quote.price, quote.currency)} ≥ ${
            fmtPrice(p.take_profit ?? 0, p.currency)
          }`,
        },
      ];

      const quiet = inQuietHours(settings.quiet_from, settings.quiet_to, hourIn(tz));

      for (const c of conditions) {
        const prev = stateMap.get(stateKey(p.id, c.kind))?.active ?? false;
        if (!c.hit) {
          if (prev) {
            stateUpserts.push({
              position_id: p.id,
              kind: c.kind,
              user_id: p.user_id,
              active: false,
            });
          }
          continue;
        }
        if (prev) continue; // schon gemeldet, erst nach Entspannung erneut
        if (quiet) continue; // Ruhezeit: später erneut prüfen

        const extra = settings.include_amounts && pnlEur !== null && valueEur !== null
          ? `\nWert ${eur(valueEur)} · ${pnlEur >= 0 ? "+" : ""}${eur(pnlEur)}`
          : "";
        const result = await notify(settings, c.title, `${c.body}${extra}`);
        if (result.errors.length) errors.push(...result.errors);
        if (result.delivered.length) alertsSent++;
        events.push({
          user_id: p.user_id,
          position_id: p.id,
          kind: c.kind,
          message: `${c.title} – ${c.body}`,
          price: quote.price,
          pct: ratio,
          delivered: result.delivered,
        });
        stateUpserts.push({
          position_id: p.id,
          kind: c.kind,
          user_id: p.user_id,
          active: true,
          last_sent: new Date().toISOString(),
        });
      }
    });

    // --- Tagesübersicht verschicken
    if (mode === "daily") {
      for (const [userId, d] of daily) {
        const s = settingsByUser.get(userId);
        if (!s || !s.alerts_enabled || !s.daily_snapshot || d.lines.length === 0) continue;
        // Zwei Cron-Läufe (Sommer-/Winterzeit) – nur der um 21 Uhr lokal zählt.
        if (hourIn(s.timezone) !== 21) continue;
        const head = s.include_amounts
          ? `Wert ${eur(d.value)} · ${d.pnl >= 0 ? "+" : ""}${eur(d.pnl)}`
          : `${d.lines.length} offene Positionen`;
        const result = await notify(s, "📊 Tagesübersicht", `${head}\n\n${d.lines.join("\n")}`);
        if (result.errors.length) errors.push(...result.errors);
        if (result.delivered.length) alertsSent++;
        events.push({
          user_id: userId,
          position_id: null,
          kind: "daily",
          message: `Tagesübersicht: ${d.lines.length} Positionen`,
          delivered: result.delivered,
        });
      }
    }

    if (snapshots.length) {
      const { error } = await db.from("price_snapshots").insert(snapshots);
      if (error) errors.push(`snapshots: ${error.message}`);
    }
    if (events.length) {
      const { error } = await db.from("alert_events").insert(events);
      if (error) errors.push(`events: ${error.message}`);
    }
    if (stateUpserts.length) {
      const { error } = await db.from("alert_state").upsert(stateUpserts, {
        onConflict: "position_id,kind",
      });
      if (error) errors.push(`state: ${error.message}`);
    }
  } catch (e) {
    errors.push(e instanceof Error ? `${e.message}` : `${e}`);
  }

  await db.from("backend_runs").insert({
    kind: mode,
    checked,
    alerts: alertsSent,
    errors: errors.slice(0, 20),
  });

  return Response.json({ mode, checked, alerts: alertsSent, errors });
});
