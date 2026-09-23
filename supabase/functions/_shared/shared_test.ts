// Tests der Backend-Logik: deno test supabase/functions/_shared/shared_test.ts
// Die FIFO-Fälle entsprechen test/fifo_test.dart – beide müssen gleich rechnen.

import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { computeLedger, type Txn } from "./fifo.ts";
import { hourIn, inQuietHours, pct, price, weekdayIn } from "./notify.ts";

const buy = (quantity: number, p: number, day: string, fees = 0, fx = 1): Txn => ({
  side: "buy",
  quantity,
  price: p,
  fees,
  taxes: 0,
  fx_rate: fx,
  executed_at: `${day}T10:00:00Z`,
});

const sell = (quantity: number, p: number, day: string, fees = 0, fx = 1): Txn => ({
  side: "sell",
  quantity,
  price: p,
  fees,
  taxes: 0,
  fx_rate: fx,
  executed_at: `${day}T10:00:00Z`,
});

Deno.test("FIFO: Kauf und Verkauf mit Gebühren", () => {
  const l = computeLedger([buy(10, 100, "2026-01-02", 1), sell(10, 110, "2026-02-02", 1)]);
  assertAlmostEquals(l.realizedEur, 98, 1e-9);
  assertAlmostEquals(l.openQty, 0, 1e-9);
});

Deno.test("FIFO: Teilverkauf nimmt den ältesten Posten zuerst", () => {
  const l = computeLedger([
    buy(10, 100, "2026-01-01"),
    buy(10, 200, "2026-01-10"),
    sell(15, 150, "2026-02-01"),
  ]);
  assertAlmostEquals(l.realizedEur, 250, 1e-9);
  assertAlmostEquals(l.openQty, 5, 1e-9);
  assertAlmostEquals(l.openCostEur, 1000, 1e-9);
  assertAlmostEquals(l.avgOpenPrice ?? 0, 200, 1e-9);
});

Deno.test("FIFO: Kaufgebühren stecken im Einstand", () => {
  const l = computeLedger([buy(4, 50, "2026-01-01", 2), sell(1, 50, "2026-01-02")]);
  assertAlmostEquals(l.realizedEur, -0.5, 1e-9);
  assertAlmostEquals(l.openCostEur, 151.5, 1e-9);
});

Deno.test("FIFO: Fremdwährung mit unterschiedlichen Kursen", () => {
  const l = computeLedger([
    buy(10, 100, "2026-01-01", 0, 1.25),
    sell(10, 100, "2026-02-01", 0, 1.0),
  ]);
  assertAlmostEquals(l.realizedEur, 200, 1e-9);
});

Deno.test("FIFO: Krypto-Bruchteile lassen keinen Rest", () => {
  const l = computeLedger([
    buy(0.1, 60000, "2026-01-01"),
    buy(0.2, 60000, "2026-01-02"),
    sell(0.3, 70000, "2026-01-03"),
  ]);
  assertAlmostEquals(l.openQty, 0, 1e-9);
  assertAlmostEquals(l.realizedEur, 3000, 1e-6);
  assertEquals(l.avgOpenPrice, null);
});

Deno.test("Ruhezeit über Mitternacht", () => {
  assertEquals(inQuietHours(22, 7, 23), true);
  assertEquals(inQuietHours(22, 7, 3), true);
  assertEquals(inQuietHours(22, 7, 7), false);
  assertEquals(inQuietHours(22, 7, 15), false);
  assertEquals(inQuietHours(0, 0, 4), false);
});

Deno.test("Lokale Zeit in Europe/Berlin", () => {
  // 22.09.2026 ist ein Dienstag; 18:00 UTC = 20:00 Berlin (Sommerzeit).
  const d = new Date("2026-09-22T18:00:00Z");
  assertEquals(hourIn("Europe/Berlin", d), 20);
  assertEquals(weekdayIn("Europe/Berlin", d), 2);
  // Winterzeit: 20:00 UTC = 21:00 Berlin
  assertEquals(hourIn("Europe/Berlin", new Date("2026-12-01T20:00:00Z")), 21);
});

Deno.test("Formatierung deutsch", () => {
  assertEquals(pct(0.1234), "+12,34 %");
  assertEquals(pct(-0.05), "-5 %");
  assertEquals(price(182.72, "EUR"), "182,72 €");
  assertEquals(price(0.0123, "EUR"), "0,0123 €");
});
