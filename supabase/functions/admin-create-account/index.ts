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

  const authHeader = req.headers.get("Authorization") || "";
  const tokenFromSession = authHeader.replace(/^Bearer\s+/i, "");
  if (!tokenFromSession || tokenFromSession === authHeader) {
    return respond({ error: "Debes iniciar sesión como administrador." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return respond({ error: "La función no tiene configuradas las credenciales del servidor." }, 500);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: callerData, error: callerError } = await callerClient.auth.getUser(tokenFromSession);
  if (callerError || !callerData.user) return respond({ error: "Sesión inválida o vencida." }, 401);

  const { data: callerProfile, error: profileError } = await adminClient
    .from("users").select("role").eq("id", callerData.user.id).maybeSingle();
  if (profileError || callerProfile?.role !== "admin") {
    return respond({ error: "Solo un administrador puede crear cuentas." }, 403);
  }

  let input: Record<string, unknown>;
  try { input = await req.json(); } catch { return respond({ error: "Solicitud inválida." }, 400); }

  const email = String(input.email || "").trim().toLowerCase();
  const password = String(input.password || "");
  const name = String(input.name || "").trim();
  const phone = String(input.phone || "").trim();
  const role = String(input.role || "");
  const shopName = String(input.shopName || "").trim();
  const address = String(input.address || "").trim();
  const deliveryFee = Number(input.deliveryFee ?? 0);

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond({ error: "Introduce un correo válido." }, 400);
  if (password.length < 10) return respond({ error: "La contraseña inicial debe tener al menos 10 caracteres." }, 400);
  if (!name || name.length > 120) return respond({ error: "El nombre es obligatorio y debe tener máximo 120 caracteres." }, 400);
  if (phone.length > 40) return respond({ error: "El teléfono es demasiado largo." }, 400);
  if (!["technician", "shop"].includes(role)) return respond({ error: "Solo puedes crear perfiles de técnico o tienda." }, 400);
  if (role === "shop" && !shopName) return respond({ error: "El nombre de la tienda es obligatorio." }, 400);
  if (shopName.length > 160 || address.length > 240) return respond({ error: "Los datos de la tienda son demasiado largos." }, 400);
  if (role === "technician" && (!address || address.length < 6)) return respond({ error: "La dirección del técnico es obligatoria y debe tener al menos 6 caracteres." }, 400);
  if (role === "technician" && (!Number.isFinite(deliveryFee) || deliveryFee < 0 || deliveryFee > 1000000)) return respond({ error: "La tarifa de domicilio debe ser un valor válido entre $0 y $1.000.000." }, 400);

  const authorizationToken = crypto.randomUUID();
  const { error: tokenError } = await adminClient.from("account_authorization_tokens").insert({
    token: authorizationToken,
    email,
    role,
    full_name: name,
    phone: phone || null,
    expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
  });
  if (tokenError) {
    return respond({ error: "No se pudo preparar la autorización de alta." }, 500);
  }

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      name,
      phone: phone || null,
      role,
      _account_token: authorizationToken,
    },
  });

  if (createError || !created.user) {
    await adminClient.from("account_authorization_tokens").delete().eq("token", authorizationToken);
    const message = createError?.message || "No se pudo crear la cuenta.";
    const duplicate = /already|registered|exists/i.test(message);
    return respond({ error: duplicate ? "Ese correo ya tiene una cuenta." : message }, duplicate ? 409 : 400);
  }

  // Remove the one-time authorization token from metadata after the trigger validates it.
  const { error: metadataError } = await adminClient.auth.admin.updateUserById(created.user.id, {
    user_metadata: { name, phone: phone || null, role },
  });
  if (metadataError) {
    await adminClient.auth.admin.deleteUser(created.user.id);
    return respond({ error: "No se pudo finalizar la creación del perfil. Intenta de nuevo." }, 500);
  }

  if (role === "technician") {
    const { error: technicianError } = await adminClient.from("users").update({ address, delivery_fee: deliveryFee }).eq("id", created.user.id);
    if (technicianError) {
      await adminClient.auth.admin.deleteUser(created.user.id);
      return respond({ error: "No se pudo guardar la dirección y tarifa del técnico. La cuenta fue revertida." }, 500);
    }
  }

  if (role === "shop") {
    const { error: shopError } = await adminClient.from("shops").insert({
      user_id: created.user.id,
      name: shopName,
      address: address || null,
      active: false,
      status: "pending",
      delivery_local_fee: 0,
      delivery_outside_fee: 5000,
    });
    if (shopError) {
      await adminClient.auth.admin.deleteUser(created.user.id);
      return respond({ error: "No se pudo crear la ficha de tienda. La cuenta fue revertida." }, 500);
    }
  }

  return respond({
    success: true,
    user: { id: created.user.id, email, name, phone: phone || null, role },
    shopStatus: role === "shop" ? "pending" : null,
  }, 201);
});
