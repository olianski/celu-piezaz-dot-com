const fs = require("fs");
const assert = require("assert");

const html = fs.readFileSync(process.argv[2] || "index.html", "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1] || "";

assert(script, "No se encontró el bloque JavaScript principal.");

const ids = [...html.matchAll(/id=["']([^"']+)["']/g)].map(m => m[1]);
const counts = ids.reduce((a,id)=>(a[id]=(a[id]||0)+1,a),{});
const duplicateIds = Object.entries(counts).filter(([,n])=>n>1);
assert.deepStrictEqual(duplicateIds, [], "Hay IDs HTML duplicados.");

assert.strictEqual((script.match(/function\s+renderModels\s*\(/g)||[]).length, 1,
  "Debe existir una sola función renderModels.");

assert(!html.includes("/* v6 — tienda: selector amigable del catálogo maestro */"),
  "Quedó código legacy v6.");

assert(!html.includes("spSearchBtn"),
  "Quedó referencia al botón legacy spSearchBtn.");

assert(html.includes("window.renderStoreProductPicker=function"),
  "Falta el picker activo de tienda.");

assert(html.includes('String(x.productId)===String(productId)'),
  "inventoryFor debe normalizar IDs.");

console.log("PASS: estructura HTML, picker activo, código legacy e IDs");
