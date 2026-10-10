import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ error: "Método no permitido." }, 405);

  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token || token === authorization) return respond({ error: "Debes iniciar sesión como administrador." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return respond({ error: "Falta configuración del servidor." }, 500);

  const caller = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const db = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData.user) return respond({ error: "Sesión inválida o vencida." }, 401);

  const { data: admin, error: adminError } = await db.from("users").select("role").eq("id", authData.user.id).maybeSingle();
  if (adminError || admin?.role !== "admin") return respond({ error: "Solo un administrador puede eliminar cuentas." }, 403);

  let input: Record<string, unknown>;
  try { input = await req.json(); } catch { return respond({ error: "Solicitud inválida." }, 400); }
  const userId = String(input.userId || "").trim();
  if (!userId) return respond({ error: "Falta la cuenta que deseas eliminar." }, 400);
  if (userId === authData.user.id) return respond({ error: "No puedes eliminar tu propia cuenta de administrador." }, 403);

  const { data, error } = await db.rpc("admin_delete_account", {
    p_user_id: userId,
    p_admin_id: authData.user.id,
  });
  if (error) {
    const message = error.message || "No se pudo eliminar la cuenta.";
    const known = ["No se encontró la cuenta.", "Solo se pueden eliminar técnicos o tiendas.", "No puedes eliminar tu propia cuenta de administrador."];
    return respond({ error: known.includes(message) ? message : "No se pudo completar la eliminación. No se confirmaron cambios parciales." }, 400);
  }
  return respond({ success: data === true });
});
