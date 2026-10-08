# Auditoría y plan V39 — Celu Piezaz Dot Com

## Estado
GitHub está conectado correctamente y el repositorio es accesible con permisos de administración y escritura.

La rama de trabajo es `cleanup/v39-base`.

## Correcciones verificadas sobre la copia local disponible
Se trabajó sobre la última copia HTML que el sistema de archivos del proyecto expuso.

Se hicieron estas correcciones:

1. Se eliminó el bloque legacy **v6** que intentaba montar un segundo selector de catálogo.
2. Se dejó un único `renderModels()` activo.
3. Se eliminó la referencia legacy `spSearchBtn`.
4. Se mantuvo el picker activo de tienda mediante `renderStoreProductPicker()`.
5. `inventoryFor()` ahora compara IDs con `String()`, evitando fallos cuando un ID llega como número y otro como texto.
6. Se comprobó que no existen IDs HTML duplicados.

## Pruebas estáticas

Resultado sobre la copia corregida:

- IDs HTML duplicados: **0**
- `renderModels()` duplicados: **0** (queda 1)
- referencia `spSearchBtn`: **0**
- bloque legacy v6: **0**
- normalización de IDs en `inventoryFor()`: **OK**
- sintaxis JavaScript extraída del HTML: **OK** con `node --check`

Además se añadió una prueba automatizada en:

`tests/static-v39.js`

## Importante
Todavía no considero completada una prueba E2E real de navegador. Chromium está bloqueado por el entorno para navegar archivos HTML locales. No voy a afirmar que el flujo visual fue probado si no lo fue.

## Siguiente paso técnico
El código de aplicación debe quedar versionado dentro del repositorio y entonces ejecutar estas pruebas sobre el archivo real de GitHub:

- Crear inventario → guardar → limpiar formulario.
- Confirmación visual de guardado.
- Crear segundo producto inmediatamente.
- Editar precio/cantidad.
- Buscar inventario.
- Persistencia después de recargar.
- Técnico → búsqueda → pedido.
- Aceptar/finalizar pedido.
- Rechazar pedido → restaurar stock.
- Pantallas Android/iPhone.

## Corrección respecto al informe anterior
El informe anterior señalaba como problema una segunda arquitectura activa de `renderStoreProductPicker()`. Eso era impreciso: esa función pertenece al picker activo. El problema real era el bloque legacy v6 que convivía con él. V39 elimina ese bloque.
