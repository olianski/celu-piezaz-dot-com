import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ error: "Método no permitido." }, 405);
  const auth = req.headers.get("Authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token || token === auth) return respond({ error: "Debes iniciar sesión como administrador." }, 401);
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return respond({ error: "Falta configuración del servidor." }, 500);
  const caller = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const db = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData.user) return respond({ error: "Sesión inválida o vencida." }, 401);
  const { data: admin } = await db.from("users").select("role").eq("id", authData.user.id).maybeSingle();
  if (admin?.role !== "admin") return respond({ error: "Solo un administrador puede editar perfiles." }, 403);
  let input: Record<string, unknown>;
  try { input = await req.json(); } catch { return respond({ error: "Solicitud inválida." }, 400); }
  const action = String(input.action || ""), userId = String(input.userId || "");
  if (!userId) return respond({ error: "Falta el usuario que deseas editar." }, 400);
  const { data: profile, error: profileError } = await db.from("users").select("id,name,phone,role,address,delivery_fee").eq("id", userId).maybeSingle();
  if (profileError || !profile) return respond({ error: "No se encontró el perfil." }, 404);
  if (!["technician", "shop"].includes(profile.role)) return respond({ error: "Solo se pueden editar perfiles de técnicos y tiendas." }, 403);
  const { data: shop, error: shopError } = await db.from("shops").select("id,name,address,status,active,delivery_local_fee,delivery_outside_fee").eq("user_id", userId).maybeSingle();
  if (shopError) return respond({ error: "No se pudieron consultar los datos de la tienda." }, 500);
  if (action === "get") return respond({ profile, shop: shop || null });
  if (action !== "update") return respond({ error: "Acción no válida." }, 400);
  const name = String(input.name ?? "").trim(), phone = String(input.phone ?? "").trim();
  if (!name || name.length > 120) return respond({ error: "El nombre es obligatorio (máximo 120 caracteres)." }, 400);
  if (phone.length > 40) return respond({ error: "El teléfono no puede superar 40 caracteres." }, 400);
  let userChanges: Record<string, unknown> = { name, phone: phone || null };
  let shopChanges: Record<string, unknown> | null = null;
  if (profile.role === "technician") {
    const address = String(input.address ?? "").trim(), fee = Number(input.deliveryFee);
    if (address.length < 6 || address.length > 240) return respond({ error: "La dirección del técnico debe tener entre 6 y 240 caracteres." }, 400);
    if (!Number.isFinite(fee) || fee < 0 || fee > 1000000) return respond({ error: "La tarifa debe estar entre $0 y $1.000.000." }, 400);
    userChanges = { ...userChanges, address, delivery_fee: fee };
  } else {
    if (!shop) return respond({ error: "Este usuario no tiene una tienda asociada." }, 409);
    const shopName = String(input.shopName ?? "").trim(), address = String(input.address ?? "").trim();
    if (!shopName || shopName.length > 160) return respond({ error: "El nombre comercial es obligatorio (máximo 160 caracteres)." }, 400);
    if (address.length > 240) return respond({ error: "La dirección no puede superar 240 caracteres." }, 400);
    shopChanges = { name: shopName, address: address || null };
  }
  const { error: updateUserError } = await db.from("users").update(userChanges).eq("id", userId);
  if (updateUserError) return respond({ error: "No se pudieron guardar los datos del perfil." }, 500);
  if (shopChanges && shop) {
    const { error } = await db.from("shops").update(shopChanges).eq("id", shop.id);
    if (error) return respond({ error: "Se guardaron los datos del responsable, pero no se pudieron guardar los datos comerciales de la tienda." }, 500);
  }
  return respond({ success: true, message: "Perfil actualizado correctamente." });
});