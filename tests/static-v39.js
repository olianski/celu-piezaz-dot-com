const fs = require("fs");
const assert = require("assert");

const html = fs.readFileSync(process.argv[2] || "index.html", "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1] || "";

assert(script, "No se encontró el bloque JavaScript principal.");

const htmlMarkup = html.replace(/<script\b[\s\S]*?<\/script>/gi, "").replace(/<style\b[\s\S]*?<\/style>/gi, "");
const ids = [...htmlMarkup.matchAll(/\bid=["']([^"']+)["']/g)].map(m => m[1]);
const counts = ids.reduce((a,id)=>(a[id]=(a[id]||0)+1,a),{});
const duplicateIds = Object.entries(counts).filter(([,n])=>n>1);
assert.deepStrictEqual(duplicateIds, [], "Hay IDs HTML duplicados.");

assert(script.includes("function bootAuthenticated"),
  "Falta el arranque autenticado de la aplicación.");

assert(!html.includes("/* v6 — tienda: selector amigable del catálogo maestro */"),
  "Quedó código legacy v6.");

assert(!html.includes("spSearchBtn"),
  "Quedó referencia al botón legacy spSearchBtn.");

assert(html.includes("window.renderStoreProductPicker=function"),
  "Falta el picker activo de tienda.");

assert(html.includes('String(x.productId)===String(productId)'),
  "inventoryFor debe normalizar IDs.");


const vm = require("vm");
const path = require("path");
new vm.Script(script, { filename: "app/index.html:inline-script" });
const adapterPath = path.join(path.dirname(process.argv[2] || "index.html"), "backend-adapter.js");
const adapter = fs.readFileSync(adapterPath, "utf8");
new vm.Script(adapter, { filename: adapterPath });
assert(html.includes('id="adminConsole"'), "Falta la consola independiente de administración.");
assert(html.includes('openPage("adminConsole")'), "El login de administrador no abre la nueva consola.");
assert(!html.includes('id="techBanner"')&&!html.includes("Modo Técnico"), "No debe quedar el banner de prueba en ningún rol.");
assert(html.includes('body.role-technician #navAdmin{display:none!important}'), "El técnico no debe ver la navegación Mi tienda.");
assert(html.includes('body.role-shop #navMarket{display:none!important}'), "La tienda no debe ver Buscar como si fuera técnico.");
assert(html.includes('function openShopHome()'), "El acceso Mi tienda debe abrir su sección de inventario.");
assert(html.includes('activeShopSection==="orders"'), "La navegación de tienda debe resaltar la sección activa.");
assert(html.includes('["market","product","checkout"].includes(id)'), "Buscar debe mantenerse activo en el flujo de compra.");
assert(html.includes('Esta cuenta no tiene una tienda vinculada.'), "El perfil de tienda sin ficha debe mostrar un aviso claro.");

assert(html.includes('adminConsoleNav(\'shops\')'), "Falta la navegación de tiendas.");
assert(html.includes('adminConsoleNav(\'catalog\')'), "Falta la navegación del catálogo.");
assert(adapter.includes("adminSetShopStatus"), "Falta la gestión de estados de tiendas.");
assert(adapter.includes("Ya tienes una solicitud abierta para este repuesto."), "Las solicitudes repetidas deben mostrar un mensaje claro.");
assert(adapter.includes("from('inventory').update({active:false}).in('product_id',ids)"), "Al desactivar entradas del catálogo se debe ocultar también su inventario.");
assert(adapter.includes("Ese tipo de repuesto ya existe."), "El alta de tipos debe informar duplicados con claridad.");
assert(adapter.includes("Esa variante ya existe para el tipo seleccionado."), "El alta de variantes debe informar duplicados con claridad.");
assert(adapter.includes("adminCreateProduct"), "Falta la creación de productos maestros.");
assert(adapter.includes("adminSetUserRole"), "Falta la gestión de roles.");
assert(adapter.includes("Solo puedes asignar roles de técnico o tienda."), "No se deben asignar nuevos administradores.");
assert(adapter.includes("eq('shops.active',true)"), "La búsqueda no debe mostrar inventario de tiendas inactivas.");
assert(adapter.includes("code==='23505'"), "El alta de modelos debe detectar duplicados.");
assert(adapter.includes("Ese modelo ya existe en el catálogo"), "Falta el mensaje claro para modelos repetidos.");
assert(html.includes('localStorage.removeItem("celu_piezaz_real_v1")'), "Debe limpiar residuos locales de prueba.");
assert(!html.includes("funciones locales de prueba"), "Quedó texto de funciones de demostración.");
assert(html.includes('Empieza buscando un modelo'), "Debe mostrarse un estado vacío útil antes de buscar.");
assert(html.includes('if(step)step.style.display="none"'), "El contador de disponibilidad debe ocultarse hasta seleccionar modelo.");
assert(html.includes('Iniciar preparación')&&html.includes('Marcar en camino'), "Faltan pasos intermedios del flujo de pedido.");
assert(html.includes("function escapeHtml(value)"), "Falta escapar texto dinámico del catálogo.");
assert(html.includes("function inlineArg(value)"), "Falta codificar de forma segura los argumentos de los selectores.");
assert(html.includes("chooseStoreModelV38('+inlineArg(m)+')"), "El selector de modelo de tienda debe escapar los argumentos.");
assert(html.includes("chooseStoreVariantV38('+inlineArg(model)+','+inlineArg(type)+','+inlineArg(v)+')"), "El selector de variantes de tienda debe escapar los argumentos.");
assert(!/body\.role-(?:technician|admin|active) #techBanner/.test(html), "Quedaron reglas obsoletas del banner de prueba.");


assert(!html.includes('id="signupTab"'), "El registro público sigue visible.");
assert(!adapter.includes("auth.signUp"), "El adaptador todavía permite registro público.");
assert(html.includes("adminConsoleCreateAccount"), "Falta el formulario de alta administrativa.");
assert(adapter.includes("functions.invoke('admin-create-account'"), "El alta no usa la función segura del servidor.");


console.log("PASS: HTML/IDs, sintaxis JS, consola admin, registro privado, deduplicación y limpieza de demo");
