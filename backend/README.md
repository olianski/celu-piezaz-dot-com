# Backend — Fase 2

Base inicial para PostgreSQL/Supabase.

## Incluye
- Supabase Auth para identidad.
- Usuarios con roles: admin, shop y technician.
- Tiendas, catálogo maestro, inventario, pedidos y solicitudes de disponibilidad.
- Row Level Security (RLS) para separar los datos por rol.
- Índices y relaciones principales.
- Tarifas de entrega parametrizadas.

## Siguiente integración
1. Provisionar el proyecto Supabase.
2. Ejecutar la migración.
3. Cargar el catálogo maestro.
4. Crear usuarios iniciales.
5. Implementar operaciones transaccionales de pedido y stock.
6. Conectar el frontend aprobado sin rediseñarlo.