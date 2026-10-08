const fs=require('fs');
const files=process.argv.slice(2);
if(!files.length) throw new Error('Indica archivos SQL a revisar');
for(const f of files){
  const s=fs.readFileSync(f,'utf8');
  const checks=[];
  if(f.includes('004')) checks.push([/handle_new_user[\\s\\S]*?'technician'/,'registro seguro'],[/save_inventory_item/,'RPC inventario'],[/update_order_status/,'RPC estados'],[/status='approved'/,'tienda aprobada'],[/orders_status_check/,'estados permitidos'],[/search_products/,'RPC búsqueda']);
  if(f.includes('002_order_transaction')) checks.push([/for update/,'bloqueo stock'],[/quantity\s*=\s*quantity\s*-\s*v_qty/,'descuento stock']);
  if(f.includes('003_auth_profile')) checks.push([/on_auth_user_created/,'trigger auth']);
  for(const [re,label] of checks) if(!re.test(s)) throw new Error(f+': falta '+label);
}
console.log('Backend static checks OK');