// Celu Piezaz Dot Com — adaptador backend.
// No modifica el diseño. Centraliza la futura conexión con Supabase.
window.CeluPiezazBackend = (() => {
  let client = null;

  function configure(supabaseClient) {
    client = supabaseClient;
    return client;
  }

  function ready() {
    return !!client;
  }

  async function signIn(email, password) {
    if (!client) throw new Error("Backend no configurado");
    return client.auth.signInWithPassword({ email, password });
  }

  async function signOut() {
    if (!client) throw new Error("Backend no configurado");
    return client.auth.signOut();
  }

  async function session() {
    if (!client) return { data: { session: null }, error: null };
    return client.auth.getSession();
  }

  async function searchProducts(search) {
    if (!client) throw new Error("Backend no configurado");
    return client
      .from("products")
      .select("id,display_name,normalized_search,phone_models(brand,model),part_types(name),part_variants(name)")
      .eq("active", true)
      .ilike("normalized_search", "%" + String(search || "").trim().toLowerCase() + "%");
  }

  async function getInventoryByProduct(productId) {
    if (!client) throw new Error("Backend no configurado");
    return client
      .from("inventory")
      .select("id,shop_id,product_id,price,quantity,shops(id,name,address,delivery_local_fee,delivery_outside_fee)")
      .eq("product_id", productId)
      .eq("active", true)
      .gt("quantity", 0);
  }

  async function saveInventory(shopId, productId, price, quantity) {
    if (!client) throw new Error("Backend no configurado");
    return client.from("inventory").upsert({
      shop_id: shopId,
      product_id: productId,
      price: Number(price),
      quantity: Number(quantity),
      active: true
    }, { onConflict: "shop_id,product_id" });
  }

  async function placeOrder(shopId, deliveryType, deliveryAddress, items) {
    if (!client) throw new Error("Backend no configurado");
    return client.rpc("place_order", {
      p_shop_id: shopId,
      p_delivery_type: deliveryType,
      p_delivery_address: deliveryAddress || null,
      p_items: items
    });
  }

  return {
    configure, ready, signIn, signOut, session,
    searchProducts, getInventoryByProduct, saveInventory, placeOrder
  };
})();
