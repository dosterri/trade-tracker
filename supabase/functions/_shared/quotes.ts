// Kursquellen – Spiegelbild von lib/data/quote_sources.dart.
// Inoffizielle Schnittstellen (LS, onvista): Ausfälle sind eingeplant, jede
// Quelle wirft im Fehlerfall und wird pro Position einzeln abgefangen.

export interface Quote {
  price: number;
  currency: string;
  at: string;
  source: string;
}

const TIMEOUT_MS = 12_000;

async function getJson(url: string, headers: Record<string, string> = {}): Promise<unknown> {
  const res = await fetch(url, {
    headers: { accept: "application/json", ...headers },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`${new URL(url).host}: HTTP ${res.status}`);
  return await res.json();
}

/** Lang & Schwarz Exchange – Aktien/ETFs, dieselben Kurse wie bei Trade Republic. */
export async function lsQuote(instrumentId: string): Promise<Quote> {
  const url = (series: string) =>
    `https://www.ls-tc.de/_rpc/json/instrument/chart/dataForInstrument` +
    `?instrumentId=${encodeURIComponent(instrumentId)}&marketId=1&quotetype=mid` +
    `&series=${series}&localeId=2`;

  const read = (raw: unknown, series: string): [number, number][] => {
    const data = (raw as Record<string, Record<string, { data?: unknown }>>)
      ?.series?.[series]?.data;
    return Array.isArray(data) ? data as [number, number][] : [];
  };

  let points = read(await getJson(url("intraday")), "intraday");
  if (points.length < 1) points = read(await getJson(url("history")), "history");
  const last = points.at(-1);
  if (!last) throw new Error("Lang & Schwarz: keine Kurse");
  return {
    price: Number(last[1]),
    currency: "EUR",
    at: new Date(Number(last[0])).toISOString(),
    source: "ls",
  };
}

/** onvista – Derivate und Fallback. `ref` = "ENTITYTYPE/ID". */
export async function onvistaQuote(ref: string, preferBid = false): Promise<Quote> {
  const [type, id] = ref.split("/");
  if (!type || !id) throw new Error("onvista: ungültige Referenz");
  const raw = await getJson(
    `https://api.onvista.de/api/v1/instruments/${encodeURIComponent(type)}/${
      encodeURIComponent(id)
    }/snapshot`,
  ) as { quote?: Record<string, unknown> };
  const q = raw.quote;
  if (!q) throw new Error("onvista: kein Kurs");
  const bid = typeof q.bid === "number" ? q.bid : null;
  const last = typeof q.last === "number" ? q.last : null;
  const useBid = preferBid && bid !== null && bid > 0;
  const price = useBid ? bid : last;
  if (price === null) throw new Error("onvista: kein Kurs");
  const at = (useBid ? q.datetimeBid : null) ?? q.datetimeLast;
  return {
    price,
    currency: typeof q.isoCurrency === "string" ? q.isoCurrency : "EUR",
    at: typeof at === "string" ? new Date(at).toISOString() : new Date().toISOString(),
    source: "onvista",
  };
}

/** CoinGecko – Krypto direkt in EUR. */
export async function coingeckoQuote(coinId: string, demoKey = ""): Promise<Quote> {
  const raw = await getJson(
    `https://api.coingecko.com/api/v3/simple/price?ids=${
      encodeURIComponent(coinId)
    }&vs_currencies=eur&include_last_updated_at=true`,
    demoKey ? { "x-cg-demo-api-key": demoKey } : {},
  ) as Record<string, { eur?: number; last_updated_at?: number }>;
  const entry = raw[coinId];
  if (!entry || typeof entry.eur !== "number") throw new Error("CoinGecko: kein Kurs");
  return {
    price: entry.eur,
    currency: "EUR",
    at: new Date((entry.last_updated_at ?? Date.now() / 1000) * 1000).toISOString(),
    source: "coingecko",
  };
}

/** EZB-Referenzkurse (Einheiten je 1 EUR). */
export async function fxRates(): Promise<Record<string, number>> {
  const raw = await getJson("https://api.frankfurter.dev/v1/latest?base=EUR") as {
    base?: string;
    rates?: Record<string, number>;
  };
  if (raw.base?.toUpperCase() !== "EUR") throw new Error("FX: Basis ist nicht EUR");
  const out: Record<string, number> = { EUR: 1 };
  for (const [k, v] of Object.entries(raw.rates ?? {})) out[k.toUpperCase()] = v;
  return out;
}

export interface PositionRow {
  id: string;
  asset_class: string;
  currency: string;
  price_source: string;
  source_ref: string | null;
  symbol: string | null;
  manual_price: number | null;
  manual_price_at: string | null;
}

/** Holt den Kurs gemäß hinterlegter Quelle; manuell → gespeicherter Kurs. */
export async function quoteFor(p: PositionRow, coinGeckoKey = ""): Promise<Quote | null> {
  switch (p.price_source) {
    case "ls":
      if (!p.source_ref) throw new Error("Keine LS-ID hinterlegt");
      return await lsQuote(p.source_ref);
    case "onvista":
      if (!p.source_ref) throw new Error("Keine onvista-ID hinterlegt");
      return await onvistaQuote(p.source_ref, p.asset_class === "derivative");
    case "coingecko": {
      const id = p.source_ref ?? p.symbol;
      if (!id) throw new Error("Keine CoinGecko-ID hinterlegt");
      return await coingeckoQuote(id, coinGeckoKey);
    }
    default:
      return p.manual_price === null ? null : {
        price: Number(p.manual_price),
        currency: p.currency ?? "EUR",
        at: p.manual_price_at ?? new Date().toISOString(),
        source: "manual",
      };
  }
}
