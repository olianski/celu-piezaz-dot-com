# Celu Piezaz Dot Com — Arquitectura MVP

## Regla principal
El diseño visual aprobado queda congelado. Esta fase define la estructura funcional para conectar posteriormente una base de datos y autenticación reales.

## Roles
- `admin`: propietario/administrador de la plataforma.
- `shop`: tienda/repuestera autorizada.
- `technician`: técnico/comprador.

## Entidades
1. users
2. shops
3. phone_models
4. part_types
5. part_variants
6. products
7. inventory
8. orders
9. order_items
10. deliveries
11. demand_requests

## Flujo de pedido
`pending` → `accepted` → `preparing` → `out_for_delivery` → `delivered`

Alternativas:
- `rejected`: la tienda rechaza y el stock reservado se libera.
- `cancelled`: cancelado antes de completar.

## Regla de inventario
- No permitir vender más unidades que las disponibles.
- Al confirmar un pedido, reservar/descontar la cantidad.
- Si la tienda rechaza, devolver la cantidad.
- Si llega a 0, mostrar `Agotado`.
- En backend real, la operación debe ser transaccional para evitar vender la última unidad dos veces.

## Catálogo maestro
La tienda NO escribe libremente el nombre del repuesto.
Selecciona:
`Marca → Modelo → Tipo de repuesto → Variante`

Ejemplo:
`Samsung → Galaxy A15 → Pantalla → Incell`

La tienda solo administra:
- precio
- cantidad
- disponibilidad

El administrador puede crear nuevos modelos, tipos y variantes.

## Búsqueda
Normalizar mayúsculas/minúsculas, tildes y sinónimos.
Ejemplos:
- `pantalla a15`
- `display a15`
- `lcd samsung a15`
deben encontrar productos compatibles.

## Entrega
Opciones iniciales:
- local: $0
- fuera de zona: $5.000 COP
- recogida en tienda: $0

La tarifa debe quedar parametrizada para poder cambiarla sin modificar código.

## Demanda sin stock
Si no existe disponibilidad:
`Avisarme cuando aparezca`
crea una `demand_request`.
Esto permite medir qué repuestos se están solicitando aunque ninguna tienda los tenga.

## Panel técnico
- Buscar
- Filtrar
- Comparar tiendas
- Ver precio/stock
- Pedir
- Dirección
- Tipo de entrega
- Historial y estado del pedido
- Solicitudes de disponibilidad

## Panel tienda
- Inventario
- Precio
- Cantidad
- Alertas de stock
- Pedidos entrantes
- Aceptar/rechazar
- Preparar
- En camino
- Entregado

## Panel administrador
- Resumen
- Catálogo maestro
- Tiendas autorizadas
- Usuarios
- Pedidos
- Demanda no atendida
- Ventas/comisiones (fase posterior)

## Seguridad mínima
- Contraseñas gestionadas por proveedor de autenticación; nunca guardar contraseñas en texto plano.
- Cada tienda solo puede modificar su inventario y sus pedidos.
- El técnico solo puede consultar y gestionar sus propios pedidos.
- El admin puede gestionar catálogo y tiendas.
- Validar cantidades y precios en servidor, no solo en interfaz.

## Fases
### Fase 1 — Arquitectura (esta fase)
Modelo de datos, reglas y catálogo inicial.

### Fase 2 — Backend
Autenticación, base de datos, API y control de permisos.

### Fase 3 — Conexión del frontend
Conectar el HTML móvil aprobado sin rediseñarlo.

### Fase 4 — Piloto
1–2 tiendas y técnicos reales en San José del Guaviare.

### Fase 5 — Producción
Dominio, despliegue, copias de seguridad, monitoreo y métricas.

## Monetización posterior
Primero validar uso sin cobrar. Después probar comisión por pedido; la arquitectura ya contempla pedidos y tiendas para introducirla sin rehacer el producto.