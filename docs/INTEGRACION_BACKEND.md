# Integración backend

La aplicación visual aprobada permanece intacta.

## Estado
- Base PostgreSQL/Supabase creada.
- Autenticación y perfiles preparados.
- Inventario y catálogo tienen tablas y permisos.
- Pedidos tienen una función transaccional para descontar stock.
- Este adaptador concentra las llamadas que conectaremos al frontend.

## Falta para conexión real
Se necesita un proyecto Supabase real con su URL y clave pública. No se inventan credenciales ni se guardan secretos en GitHub.

## Orden de integración
1. Autenticación.
2. Catálogo y búsqueda.
3. Inventario de tienda.
4. Pedido del técnico.
5. Historial/estado.
