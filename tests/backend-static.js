const fs=require('fs');
const files=process.argv.slice(2);
if(!files.length) throw new Error('Indica archivos SQL a revisar');

for(const f of files){
  const s=fs.readFileSync(f,'utf8');
  const checks=[];
  if(f.includes('004_tiendas_inventario')){
    checks.push(
      [s.includes("values (new.id, 'technician'"),'registro seguro'],
      [s.includes('save_inventory_item'),'RPC inventario'],
      [s.includes('update_order_status'),'RPC estados'],
      [s.includes("status='approved'"),'tienda aprobada'],
      [s.includes('orders_status_check'),'estados permitidos'],
      [s.includes('search_products'),'RPC búsqueda']
    );
  }
  if(f.includes('002_order_transaction')){
    checks.push(
      [/for\s+update/i.test(s),'bloqueo stock'],
      [/quantity\s*=\s*quantity\s*-\s*v_qty/i.test(s),'descuento stock']
    );
  }
  if(f.includes('003_auth_profile')){
    checks.push([s.includes('on_auth_user_created'),'trigger auth']);
  }
  if(f.includes('007_audit_integrity_roles_catalog')){
    checks.push(
      [s.includes('phone_models_catalog_key_uidx'),'unicidad normalizada de modelos'],
      [s.includes('products_unique_catalog_key_uidx'),'unicidad de productos por modelo/tipo/variante'],
      [s.includes('users_single_admin_uidx'),'solo una cuenta admin'],
      [s.includes('prevent_shop_self_approval'),'protección contra autoaprobación de tiendas'],
      [s.includes('where id = p_product_id and active = true'),'inventario solo de productos activos'],
      [s.includes('status = \'approved\''),'validación de tienda aprobada en pedidos']
    );
  }
  if(f.includes('008_protect_business_data_and_order_flow')){
    checks.push(
      [s.includes('for select to authenticated'),'lectura del catálogo requiere sesión'],
      [s.includes('public.guard_shop_lifecycle'),'ciclo de vida de tienda protegido'],
      [s.includes('revoke insert, update, delete on public.orders, public.order_items'),'mutaciones de pedidos solo por RPC'],
      [s.includes("p_next_status='preparing'") && s.includes("p_next_status='out_for_delivery'"),'estados intermedios de pedidos'],
      [s.includes('grant execute on function public.place_order'),'RPC de pedido autorizado']
    );
  }
  if(f.includes('009_revoke_internal_trigger_function_execution')){
    checks.push(
      [s.includes('revoke execute on function public.guard_shop_lifecycle() from public, anon, authenticated'),'helpers internos sin RPC público'],
      [s.includes('grant execute on function public.current_user_role() to authenticated'),'rol actual solo para sesiones válidas'],
      [s.includes('revoke execute on function public.handle_new_user() from public, anon, authenticated'),'trigger de registro protegido']
    );
  }
  if(f.includes('010_restrict_authenticated_writes_and_inventory_guard')){
    checks.push(
      [s.includes('alter policy inventory_insert_own on public.inventory to authenticated'),'inventario restringido a sesiones válidas'],
      [s.includes('guard_inventory_write'),'inventario validado en el servidor'],
      [s.includes("v_shop.status <> 'approved'"),'tienda aprobada antes de escribir inventario'],
      [s.includes("public.current_user_role() = 'technician'"),'solicitudes reservadas a técnicos'],
      [s.includes('from anon, public'),'sin privilegios heredados para invitados']
    );
  }
  if(f.includes('011_deduplicate_open_demand_requests')){
    checks.push([s.includes('demand_requests_one_open_per_product_uidx'),'solicitudes abiertas sin duplicados']);
  }
  if(f.includes('012_preserve_order_history_for_participants')){
    checks.push(
      [s.includes('where o.technician_id = public.users.id and s.user_id = auth.uid()'),'datos de contacto solo en pedidos propios de la tienda'],
      [s.includes('oi.product_id = public.products.id'),'producto de pedido histórico visible para participantes'],
      [s.includes('p.phone_model_id = public.phone_models.id'),'modelo histórico visible para participantes'],
      [s.includes('p.part_type_id = public.part_types.id'),'tipo de repuesto histórico visible para participantes'],
      [s.includes('p.part_variant_id = public.part_variants.id'),'variante histórica visible para participantes']
    );
  }
  for(const [ok,label] of checks) if(!ok) throw new Error(f+': falta '+label);
}
console.log('Backend static checks OK');