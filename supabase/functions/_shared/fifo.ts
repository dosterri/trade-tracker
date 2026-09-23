// FIFO-Verrechnung – Spiegelbild von lib/core/fifo.dart.
// Bei Änderungen bitte beide Seiten anpassen (Tests: test/fifo_test.dart).

export interface Txn {
  side: "buy" | "sell";
  quantity: number;
  price: number;
  fees: number;
  taxes: number;
  fx_rate: number;
  executed_at: string;
}

export interface Ledger {
  openQty: number;
  /** Einstand der offenen Stücke in EUR inkl. anteiliger Kaufgebühren. */
  openCostEur: number;
  /** Durchschnittlicher Einstandskurs in Positionswährung (ohne Gebühren). */
  avgOpenPrice: number | null;
  realizedEur: number;
}

const EPS = 1e-9;

export function computeLedger(txns: Txn[]): Ledger {
  const sorted = [...txns].sort((a, b) => {
    const d = Date.parse(a.executed_at) - Date.parse(b.executed_at);
    return d !== 0 ? d : (a.side === "buy" ? -1 : 1) - (b.side === "buy" ? -1 : 1);
  });

  const lots: { qty: number; unitPrice: number; unitCostEur: number }[] = [];
  let realized = 0;

  for (const t of sorted) {
    const qty = Number(t.quantity);
    const price = Number(t.price);
    const fees = Number(t.fees ?? 0);
    const fx = Number(t.fx_rate ?? 1);
    if (!(qty > 0) || !(fx > 0)) continue;

    if (t.side === "buy") {
      lots.push({
        qty,
        unitPrice: price,
        unitCostEur: (price + fees / qty) / fx,
      });
      continue;
    }

    const unitProceedsEur = (price - fees / qty) / fx;
    let remaining = qty;
    while (remaining > EPS && lots.length > 0) {
      const lot = lots[0];
      const take = Math.min(remaining, lot.qty);
      realized += take * (unitProceedsEur - lot.unitCostEur);
      lot.qty -= take;
      remaining -= take;
      if (lot.qty <= EPS) lots.shift();
    }
  }

  const openQty = lots.reduce((s, l) => s + l.qty, 0);
  return {
    openQty,
    openCostEur: lots.reduce((s, l) => s + l.qty * l.unitCostEur, 0),
    avgOpenPrice: openQty > EPS
      ? lots.reduce((s, l) => s + l.qty * l.unitPrice, 0) / openQty
      : null,
    realizedEur: realized,
  };
}
