// Zustellung der Meldungen: Telegram und/oder ntfy.
// Das Bot-Token kommt aus den Function-Secrets, nie aus der Datenbank.

export interface NotifySettings {
  telegram_enabled: boolean;
  telegram_chat_id: string | null;
  ntfy_enabled: boolean;
  ntfy_topic: string | null;
  ntfy_server: string;
}

export interface NotifyResult {
  delivered: string[];
  errors: string[];
}

async function sendTelegram(chatId: string, text: string): Promise<void> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  if (!token) throw new Error("TELEGRAM_BOT_TOKEN fehlt");
  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      disable_web_page_preview: true,
    }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) {
    throw new Error(`Telegram HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
}

async function sendNtfy(
  server: string,
  topic: string,
  title: string,
  text: string,
): Promise<void> {
  // JSON-Body statt Header, damit Umlaute sicher ankommen.
  const res = await fetch(server.replace(/\/+$/, ""), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ topic, title, message: text }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) {
    throw new Error(`ntfy HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
}

/** Schickt eine Meldung über alle aktiven Kanäle. Ein Ausfall stoppt den anderen nicht. */
export async function notify(
  s: NotifySettings,
  title: string,
  text: string,
): Promise<NotifyResult> {
  const delivered: string[] = [];
  const errors: string[] = [];

  if (s.telegram_enabled && s.telegram_chat_id) {
    try {
      await sendTelegram(s.telegram_chat_id, `${title}\n${text}`);
      delivered.push("telegram");
    } catch (e) {
      errors.push(`telegram: ${e instanceof Error ? e.message : e}`);
    }
  }
  if (s.ntfy_enabled && s.ntfy_topic) {
    try {
      await sendNtfy(s.ntfy_server || "https://ntfy.sh", s.ntfy_topic, title, text);
      delivered.push("ntfy");
    } catch (e) {
      errors.push(`ntfy: ${e instanceof Error ? e.message : e}`);
    }
  }
  if (delivered.length === 0 && errors.length === 0) {
    errors.push("Kein Zustellweg aktiv oder konfiguriert");
  }
  return { delivered, errors };
}

// --- Formatierung (deutsch) -------------------------------------------------

export const eur = (v: number): string =>
  new Intl.NumberFormat("de-DE", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 2,
  }).format(v);

export const pct = (ratio: number): string =>
  `${ratio > 0 ? "+" : ""}${
    new Intl.NumberFormat("de-DE", { maximumFractionDigits: 2 }).format(ratio * 100)
  } %`;

export const price = (v: number, currency: string): string => {
  const abs = Math.abs(v);
  const digits = abs >= 100 ? 2 : abs >= 1 ? 3 : abs >= 0.01 ? 4 : 6;
  const n = new Intl.NumberFormat("de-DE", {
    minimumFractionDigits: 2,
    maximumFractionDigits: digits,
  }).format(v);
  return `${n} ${currency === "EUR" ? "€" : currency}`;
};

/** Stunde (0–23) in der Zeitzone des Nutzers. */
export function hourIn(timezone: string, now = new Date()): number {
  try {
    // formatToParts statt format(): "de-DE" hängt sonst " Uhr" an.
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: timezone,
      hour: "2-digit",
      hour12: false,
    }).formatToParts(now);
    const h = Number(parts.find((p) => p.type === "hour")?.value);
    return Number.isFinite(h) ? h % 24 : now.getUTCHours();
  } catch {
    return now.getUTCHours();
  }
}

/** Wochentag 1=Mo … 7=So in der Zeitzone des Nutzers. */
export function weekdayIn(timezone: string, now = new Date()): number {
  const names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  try {
    const s = new Intl.DateTimeFormat("en-US", { timeZone: timezone, weekday: "short" })
      .format(now);
    const i = names.indexOf(s);
    return i >= 0 ? i + 1 : now.getUTCDay() || 7;
  } catch {
    return now.getUTCDay() || 7;
  }
}

/** Ruhezeit? Fenster darf über Mitternacht gehen (z. B. 22 → 7). */
export function inQuietHours(from: number, to: number, hour: number): boolean {
  if (from === to) return false;
  return from < to ? hour >= from && hour < to : hour >= from || hour < to;
}
