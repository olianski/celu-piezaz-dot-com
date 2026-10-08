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
  for(const [ok,label] of checks) if(!ok) throw new Error(f+': falta '+label);
}
console.log('Backend static checks OK');