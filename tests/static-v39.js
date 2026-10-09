const fs = require("fs");
const assert = require("assert");

const html = fs.readFileSync(process.argv[2] || "index.html", "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1] || "";

assert(script, "No se encontró el bloque JavaScript principal.");

const ids = [...html.matchAll(/id=["']([^"']+)["']/g)].map(m => m[1]);
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
assert(html.includes('body.role-technician #techBanner{display:none!important}'), "El banner de modo técnico debe ocultarse.");
assert(html.includes('body.role-technician #navAdmin{display:none!important}'), "El técnico no debe ver la navegación Mi tienda.");

assert(html.includes('adminConsoleNav(\'shops\')'), "Falta la navegación de tiendas.");
assert(html.includes('adminConsoleNav(\'catalog\')'), "Falta la navegación del catálogo.");
assert(adapter.includes("adminSetShopStatus"), "Falta la gestión de estados de tiendas.");
assert(adapter.includes("adminCreateProduct"), "Falta la creación de productos maestros.");
assert(adapter.includes("adminSetUserRole"), "Falta la gestión de roles.");
assert(!html.includes('id="signupTab"'), "El registro público sigue visible.");
assert(!adapter.includes("auth.signUp"), "El adaptador todavía permite registro público.");
assert(html.includes("adminConsoleCreateAccount"), "Falta el formulario de alta administrativa.");
assert(adapter.includes("functions.invoke('admin-create-account'"), "El alta no usa la función segura del servidor.");


console.log("PASS: HTML/IDs, sintaxis JS, consola admin, registro privado y funciones Supabase");
