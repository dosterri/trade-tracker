// Schickt eine Testnachricht über die in der App hinterlegten Kanäle.
// Wird aus der App aufgerufen und läuft mit dem Token des angemeldeten Nutzers,
// sieht also durch Row Level Security nur dessen eigene Einstellungen.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { notify, type NotifySettings } from "../_shared/notify.ts";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, apikey, x-client-info",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return Response.json({ error: "Nicht angemeldet" }, { status: 401, headers: cors });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SB_PUBLISHABLE_KEY")!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );

  const { data: user } = await db.auth.getUser();
  if (!user?.user) {
    return Response.json({ error: "Nicht angemeldet" }, { status: 401, headers: cors });
  }

  const { data, error } = await db.from("notification_settings").select("*").maybeSingle();
  if (error) {
    return Response.json({ error: error.message }, { status: 500, headers: cors });
  }
  if (!data) {
    return Response.json(
      { error: "Noch keine Benachrichtigungs-Einstellungen gespeichert" },
      { status: 400, headers: cors },
    );
  }

  const result = await notify(
    data as NotifySettings,
    "✅ Trade Tracker",
    "Testnachricht – die Zustellung funktioniert.",
  );

  return Response.json(result, {
    status: result.delivered.length > 0 ? 200 : 502,
    headers: cors,
  });
});
