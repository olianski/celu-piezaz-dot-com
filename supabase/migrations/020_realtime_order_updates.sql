-- Publicar los cambios de pedidos para que técnico y tienda reciban eventos en tiempo real.
-- Idempotente: no vuelve a agregar la tabla si ya está en supabase_realtime.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'orders'
     ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end
$$;
