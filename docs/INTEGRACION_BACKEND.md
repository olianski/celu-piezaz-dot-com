# Integración backend

La aplicación visual aprobada permanece intacta.

## Estado actual
- Supabase/PostgreSQL: esquema real preparado.
- Registro público: siempre crea técnico; una tienda requiere autorización.
- Tiendas: pendiente → aprobada → suspendida.
- Inventario: una tienda aprobada publica solo productos maestros.
- Catálogo: 109 modelos con alias de búsqueda.
- Búsqueda: multi-palabra, tildes y alias.
- Pedidos: creación transaccional con bloqueo de stock.
- Tienda: pendiente → aceptado → entregado.
- Rechazo/cancelación: devuelve el stock reservado.
- RLS: aislamiento entre tiendas y usuarios.

## Conexión real pendiente
Solo falta un proyecto Supabase real con URL y clave pública. No se inventan credenciales ni se guardan secretos en GitHub.

El frontend podrá usar `app/backend-adapter.js` sin cambiar la interfaz aprobada.