# Auditoría Celu Piezaz Dot Com — 2026-10-08

## Estado del repositorio
El repositorio estaba vacío al momento de la auditoría. La conexión GitHub funciona y la cuenta tiene permisos de administración, mantenimiento, lectura y escritura. Por eso no fue posible auditar código *del repositorio* todavía.

La auditoría técnica se realizó sobre la versión local **Celu_Piezaz_Dot_Com_TIENDA_v38_CREAR_INVENTARIO_SIN_ERRORES.html**, que es la última versión disponible del sistema.

## Pruebas realizadas

- 5 bloques JavaScript analizados.
- Los 5 bloques pasan `node --check`: **0 errores de sintaxis**.
- HTML inspeccionado: **0 IDs duplicados**.
- Se revisaron referencias DOM, funciones, eventos y flujo de Crear inventario.
- Se revisó la arquitectura de persistencia, catálogo, inventario, pedidos, ventas y navegación.
- Se intentó prueba E2E con Chromium/Playwright; el entorno de ejecución bloqueó la navegación local con `ERR_BLOCKED_BY_ADMINISTRATOR`. No se presenta esa prueba como una prueba E2E exitosa.

## Hallazgos

### Críticos
1. **El repositorio está vacío.** El código real aún no está versionado allí.
2. **Persistencia compartida:** la tienda usa `KEY="celu_piezaz_tecnico_v11"`. Esto mezcla el estado de tienda y técnico en el mismo localStorage. Puede producir contaminación entre módulos.
3. **Código histórico superpuesto:** v38 contiene lógica nueva junto con bloques legacy/fallback de versiones anteriores. Esto aumenta el riesgo de eventos duplicados y regresiones.

### Importantes
4. Hay **dos funciones `renderModels`** en el archivo, correspondientes a dos sistemas de picker distintos.
5. Existe código fallback que referencia `spSearchBtn` y `renderStoreProductPicker`, pero esos elementos/funciones no existen en la implementación activa. Actualmente parece código muerto, pero debe eliminarse.
6. El flujo legacy intenta envolver un selector antiguo, aunque el flujo actual ya tiene un picker propio. Debe eliminarse para dejar una sola fuente de verdad.
7. `inventoryFor()` compara `productId` con igualdad estricta. El sistema nuevo guarda algunos IDs como string y el estado histórico puede contener números. Conviene normalizar siempre con `String()` para evitar fallos de actualización/restauración.
8. El catálogo maestro y el catálogo operativo están mezclados dentro del HTML/estado local. Para la siguiente fase debe existir una única fuente maestra y el inventario solo debe referenciarla.

## Lo que está bien
- La lógica de guardado de Crear inventario valida precio y cantidad.
- El guardado nuevo distingue entre producto agregado y actualizado.
- Existe limpieza del formulario después del guardado.
- Existe confirmación visual de éxito.
- La búsqueda de inventario usa comparación normalizada de IDs.
- La edición de inventario limita los cambios a precio y cantidad.
- La lógica de calidades de pantalla diferencia Android e iPhone.
- La interfaz mantiene el enfoque móvil y el flujo de tienda aprobado.

## Prioridad recomendada

1. Pasar el código real a GitHub.
2. Eliminar código legacy/fallback duplicado.
3. Separar la persistencia de técnico y tienda.
4. Normalizar IDs.
5. Crear pruebas E2E automatizadas para:
   - Crear inventario.
   - Editar inventario.
   - Buscar inventario.
   - Inventario → mercado.
   - Técnico → pedido.
   - Pedido → aceptar/finalizar.
   - Rechazo → restauración de stock.
   - Pantallas Android/iPhone.
   - Persistencia tras recarga.
6. Recién después continuar agregando funcionalidades.

**Conclusión:** v38 no presenta errores de sintaxis, pero todavía necesita limpieza estructural y pruebas E2E automatizadas antes de considerarse una base sólida para seguir creciendo.
