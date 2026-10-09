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
  async function getMyShop(){ const c=requireClient(); const u=await c.auth.getUser(); return c.from('shops').select('id,user_id,name,address,delivery_local_fee,delivery_outside_fee,active,status').eq('user_id',u.data.user?.id).maybeSingle(); }
  async function getMyInventory(){ return requireClient().from('inventory').select('id,shop_id,product_id,price,quantity,active,updated_at,products(id,display_name,phone_models(brand,model),part_types(name),part_variants(name))').order('updated_at',{ascending:false}); }
  async function getInventoryByProduct(productId){ return requireClient().from('inventory').select('id,shop_id,product_id,price,quantity,shops(id,name,address,delivery_local_fee,delivery_outside_fee,status)').eq('product_id',productId).eq('active',true).gt('quantity',0).eq('shops.status','approved'); }
  async function saveInventoryItem(productId,price,quantity){ return requireClient().rpc('save_inventory_item',{p_product_id:productId,p_price:Number(price),p_quantity:Number(quantity)}); }
  async function placeOrder(shopId,deliveryType,deliveryAddress,items){ return requireClient().rpc('place_order',{p_shop_id:shopId,p_delivery_type:deliveryType,p_delivery_address:deliveryAddress||null,p_items:items}); }
  async function updateOrderStatus(orderId,nextStatus){ return requireClient().rpc('update_order_status',{p_order_id:orderId,p_next_status:nextStatus}); }
  async function listMyOrders(){ return requireClient().from('orders').select('id,technician_id,shop_id,status,delivery_type,delivery_fee,delivery_address,total,created_at,updated_at,shops!orders_shop_id_fkey(id,name,address,status),users!orders_technician_id_fkey(name,phone),order_items!order_items_order_id_fkey(id,inventory_id,product_id,quantity,unit_price,products!order_items_product_id_fkey(id,display_name,phone_model_id,part_type_id,part_variant_id,phone_models!products_phone_model_id_fkey(brand,model),part_types!products_part_type_id_fkey(name),part_variants!products_part_variant_id_fkey(name)))').order('created_at',{ascending:false}).limit(300); }
  // Funciones del panel administrativo: las políticas RLS de Supabase restringen estas operaciones a admins.
  async function listPhoneModels(){ return requireClient().from('phone_models').select('id,brand,model,normalized_name,active').eq('active',true).order('brand').order('model').limit(500); }
  async function listProductsByModel(modelId){
    return requireClient().from('products').select('id,phone_model_id,part_type_id,part_variant_id,display_name,normalized_search,active,phone_models!products_phone_model_id_fkey(brand,model),part_types!products_part_type_id_fkey(name),part_variants!products_part_variant_id_fkey(name)').eq('phone_model_id',modelId).eq('active',true).order('display_name').limit(200);
  }
  async function getInventoryByProducts(productIds){
    if(!productIds||!productIds.length)return {data:[],error:null};
    return requireClient().from('inventory').select('id,shop_id,product_id,price,quantity,active,shops!inventory_shop_id_fkey!inner(id,name,address,status,delivery_local_fee,delivery_outside_fee),products!inventory_product_id_fkey(id,display_name,phone_model_id,part_type_id,part_variant_id,phone_models!products_phone_model_id_fkey(brand,model),part_types!products_part_type_id_fkey(name),part_variants!products_part_variant_id_fkey(name))').in('product_id',productIds).eq('active',true).gt('quantity',0).eq('shops.status','approved').order('price');
  }
  async function listShopInventory(shopId){
    return requireClient().from('inventory').select('id,shop_id,product_id,price,quantity,active,updated_at,products!inventory_product_id_fkey(id,display_name,phone_model_id,part_type_id,part_variant_id,active,phone_models!products_phone_model_id_fkey(brand,model),part_types!products_part_type_id_fkey(name),part_variants!products_part_variant_id_fkey(name))').eq('shop_id',shopId).order('updated_at',{ascending:false});
  }
  async function createDemandRequest(productId){
    const c=requireClient(); const u=await c.auth.getUser();
    if(u.error) return {data:null,error:u.error};
    return c.from('demand_requests').insert({technician_id:u.data.user.id,product_id:productId,status:'open'}).select().single();
  }
  async function adminCreateAccount(payload){
    const r=await requireClient().functions.invoke('admin-create-account',{body:payload});
    if(r.error) throw r.error;
    if(r.data?.error) throw new Error(r.data.error);
    return r;
  }
  async function adminOverview(){
    const c=requireClient();
    const [users,shops,pendingShops,products,models,openOrders,openRequests,deliveredOrders]=await Promise.all([
      c.from('users').select('id',{count:'exact',head:true}),
      c.from('shops').select('id',{count:'exact',head:true}),
      c.from('shops').select('id',{count:'exact',head:true}).eq('status','pending'),
      c.from('products').select('id',{count:'exact',head:true}),
      c.from('phone_models').select('id',{count:'exact',head:true}),
      c.from('orders').select('id',{count:'exact',head:true}).in('status',['pending','accepted','preparing','out_for_delivery']),
      c.from('demand_requests').select('id',{count:'exact',head:true}).eq('status','open'),
      c.from('orders').select('total').eq('status','delivered').limit(1000)
    ]);
    for(const r of [users,shops,pendingShops,products,models,openOrders,openRequests,deliveredOrders]) if(r.error) throw r.error;
    return {users:users.count||0,shops:shops.count||0,pendingShops:pendingShops.count||0,products:products.count||0,models:models.count||0,openOrders:openOrders.count||0,openRequests:openRequests.count||0,deliveredRevenue:(deliveredOrders.data||[]).reduce((a,x)=>a+Number(x.total||0),0)};
  }
  async function adminListShops(status){
    let q=requireClient().from('shops').select('id,user_id,name,address,delivery_local_fee,delivery_outside_fee,active,status,created_at,users!shops_user_id_fkey(id,name,phone,role)').order('created_at',{ascending:false}).limit(300);
    if(status&&status!=='all') q=q.eq('status',status);
    return q;
  }
  async function adminSetShopStatus(id,status){
    if(!['pending','approved','suspended'].includes(status)) throw new Error('Estado de tienda no válido');
    return requireClient().from('shops').update({status,active:status==='approved'}).eq('id',id).select().single();
  }
  async function adminListModels(){
    return requireClient().from('phone_models').select('id,brand,model,normalized_name,active').order('brand').order('model').limit(500);
  }
  async function adminCreateModel(brand,model){
    const cleanBrand=String(brand||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().replace(/\s+/g,' ');
    const cleanModel=String(model||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().replace(/\s+/g,' ');
    const normalized_name=(cleanBrand+' '+cleanModel).toLowerCase().trim();
    const r=await requireClient().from('phone_models').insert({brand:cleanBrand,model:cleanModel,normalized_name,active:true}).select().single();
    if(r.error?.code==='23505') return {...r,error:{...r.error,message:'Ese modelo ya existe en el catálogo. No se creó un duplicado.'}};
    return r;
  }
  async function adminSetModelActive(id,active){
    const c=requireClient();
    const r=await c.from('phone_models').update({active}).eq('id',id).select().single();
    if(r.error) return r;
    if(!active){const p=await c.from('products').update({active:false}).eq('phone_model_id',id);if(p.error)return p;}
    return r;
  }
  async function adminListTypes(){
    return requireClient().from('part_types').select('id,name,active').order('name');
  }
  async function adminCreateType(name){
    return requireClient().from('part_types').insert({name:String(name||'').trim(),active:true}).select().single();
  }
  async function adminSetTypeActive(id,active){
    const c=requireClient();
    const r=await c.from('part_types').update({active}).eq('id',id).select().single();
    if(r.error)return r;
    if(!active){const p=await c.from('products').update({active:false}).eq('part_type_id',id);if(p.error)return p;}
    return r;
  }
  async function adminListVariants(){
    return requireClient().from('part_variants').select('id,part_type_id,name,active,part_types!part_variants_part_type_id_fkey(name)').order('name');
  }
  async function adminCreateVariant(typeId,name){
    return requireClient().from('part_variants').insert({part_type_id:typeId,name:String(name||'').trim(),active:true}).select().single();
  }
  async function adminSetVariantActive(id,active){
    const c=requireClient();
    const r=await c.from('part_variants').update({active}).eq('id',id).select().single();
    if(r.error)return r;
    if(!active){const p=await c.from('products').update({active:false}).eq('part_variant_id',id);if(p.error)return p;}
    return r;
  }
  async function adminListProducts(search,active){
    let q=requireClient().from('products').select('id,display_name,normalized_search,active,phone_model_id,part_type_id,part_variant_id,phone_models!products_phone_model_id_fkey(brand,model,active),part_types!products_part_type_id_fkey(name,active),part_variants!products_part_variant_id_fkey(name,active)').order('display_name').limit(250);
    if(search) q=q.ilike('display_name','%'+String(search).trim()+'%');
    if(active==='active') q=q.eq('active',true);
    if(active==='inactive') q=q.eq('active',false);
    return q;
  }
  async function adminCreateProduct(fields){
    const c=requireClient();
    let q=c.from('products').select('id',{count:'exact',head:true}).eq('phone_model_id',fields.phone_model_id).eq('part_type_id',fields.part_type_id);
    q=fields.part_variant_id?q.eq('part_variant_id',fields.part_variant_id):q.is('part_variant_id',null);
    const check=await q;
    if(check.error)throw check.error;
    if((check.count||0)>0)throw new Error('Ese producto ya existe en el catálogo.');
    return c.from('products').insert(fields).select().single();
  }
  async function adminSetProductActive(id,active){
    const c=requireClient();
    const result=await c.from('products').update({active}).eq('id',id).select().single();
    if(result.error||active)return result;
    const inventory=await c.from('inventory').update({active:false}).eq('product_id',id);
    if(inventory.error)return inventory;
    return result;
  }
  async function adminListUsers(){
    return requireClient().from('users').select('id,role,name,phone,created_at').order('created_at',{ascending:false}).limit(500);
  }
  async function adminSetUserRole(id,role){
    if(!['technician','shop'].includes(role))throw new Error('Solo puedes asignar roles de técnico o tienda.');
    const u=await requireClient().auth.getUser();
    if(u.data?.user?.id===id)throw new Error('No puedes cambiar tu propio rol de administrador.');
    return requireClient().from('users').update({role}).eq('id',id).select().single();
  }
  async function adminListOrders(){
    return requireClient().from('orders').select('id,status,delivery_type,delivery_fee,delivery_address,total,created_at,updated_at,shops!orders_shop_id_fkey(name),users!orders_technician_id_fkey(name,phone)').order('created_at',{ascending:false}).limit(300);
  }
  async function adminListDemandRequests(){
    return requireClient().from('demand_requests').select('id,status,created_at,users!demand_requests_technician_id_fkey(name,phone),products!demand_requests_product_id_fkey(display_name,phone_models(brand,model),part_types(name),part_variants(name))').order('created_at',{ascending:false}).limit(300);
  }
  async function adminSetDemandStatus(id,status){
    if(!['open','notified','closed'].includes(status))throw new Error('Estado de solicitud no válido');
    return requireClient().from('demand_requests').update({status}).eq('id',id).select().single();
  }
  return {configure,ready,signIn,profile,signOut,session,searchProducts,getMyShop,getMyInventory,getInventoryByProduct,saveInventoryItem,placeOrder,updateOrderStatus,listMyOrders,listPhoneModels,listProductsByModel,getInventoryByProducts,listShopInventory,createDemandRequest,adminCreateAccount,adminOverview,adminListShops,adminSetShopStatus,adminListModels,adminCreateModel,adminSetModelActive,adminListTypes,adminCreateType,adminSetTypeActive,adminListVariants,adminCreateVariant,adminSetVariantActive,adminListProducts,adminCreateProduct,adminSetProductActive,adminListUsers,adminSetUserRole,adminListOrders,adminListDemandRequests,adminSetDemandStatus};
})();