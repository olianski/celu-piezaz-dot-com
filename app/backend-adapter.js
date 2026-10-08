// Celu Piezaz Dot Com — adaptador backend.
// La UI no conoce tablas, RPC ni reglas de seguridad.
window.CeluPiezazBackend = (() => {
  let client = null;
  function configure(supabaseClient){ client=supabaseClient; return client; }
  function ready(){ return !!client; }
  function requireClient(){ if(!client) throw new Error('Backend no configurado'); return client; }
  async function signIn(email,password){ return requireClient().auth.signInWithPassword({email,password}); }
  async function profile(){ return requireClient().rpc('get_my_profile'); }
  async function signOut(){ return requireClient().auth.signOut(); }
  async function session(){ if(!client) return {data:{session:null},error:null}; return client.auth.getSession(); }
  async function searchProducts(search){ return requireClient().rpc('search_products',{p_query:String(search||'').trim()}); }
  async function getMyShop(){ const c=requireClient(); const u=await c.auth.getUser(); return c.from('shops').select('id,user_id,name,address,delivery_local_fee,delivery_outside_fee,active,status,approved_at').eq('user_id',u.data.user?.id).maybeSingle(); }
  async function getMyInventory(){ return requireClient().from('inventory').select('id,shop_id,product_id,price,quantity,active,updated_at,products(id,display_name,phone_models(brand,model),part_types(name),part_variants(name))').order('updated_at',{ascending:false}); }
  async function getInventoryByProduct(productId){ return requireClient().from('inventory').select('id,shop_id,product_id,price,quantity,shops(id,name,address,delivery_local_fee,delivery_outside_fee,status)').eq('product_id',productId).eq('active',true).gt('quantity',0).eq('shops.status','approved'); }
  async function saveInventoryItem(productId,price,quantity){ return requireClient().rpc('save_inventory_item',{p_product_id:productId,p_price:Number(price),p_quantity:Number(quantity)}); }
  async function placeOrder(shopId,deliveryType,deliveryAddress,items){ return requireClient().rpc('place_order',{p_shop_id:shopId,p_delivery_type:deliveryType,p_delivery_address:deliveryAddress||null,p_items:items}); }
  async function updateOrderStatus(orderId,nextStatus){ return requireClient().rpc('update_order_status',{p_order_id:orderId,p_next_status:nextStatus}); }
  async function listMyOrders(){ return requireClient().from('orders').select('id,shop_id,status,delivery_type,delivery_fee,delivery_address,total,created_at,updated_at,shops(id,name,address)').order('created_at',{ascending:false}); }
  return {configure,ready,signIn,profile,signOut,session,searchProducts,getMyShop,getMyInventory,getInventoryByProduct,saveInventoryItem,placeOrder,updateOrderStatus,listMyOrders};
})();