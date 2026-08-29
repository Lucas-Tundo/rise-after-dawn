#!/usr/bin/env node
/**
 * validate-brand.mjs — O COMPILADOR DO DESIGN
 *
 * Design é onde a IA mais alucina, porque não existe erro de compilação:
 * uma cor inventada "parece ok". Este script transforma as regras de marca
 * em testes que FALHAM. Rode no CI e em todo pre-commit.
 *
 *   node scripts/validate-brand.mjs
 *   exit 0 = aprovado | exit 1 = build quebrado
 *
 * Zero dependências: lê cabeçalho PNG direto (chunk IHDR).
 */

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";

const ROOT = process.argv[2] ?? ".";
const TOKENS = JSON.parse(readFileSync(join(ROOT, "design-tokens.json"), "utf8"));

const erros = [];
const avisos = [];
const ok = [];
const err = (m) => erros.push(m);
const warn = (m) => avisos.push(m);
const pass = (m) => ok.push(m);

/* ── Leitor de PNG sem dependências ─────────────────────────────── */
function lerPNG(caminho) {
  const b = readFileSync(caminho);
  if (b.readUInt32BE(0) !== 0x89504e47) return null;      // assinatura PNG
  const colorType = b[25];                                  // IHDR byte 9
  const bitDepth = b[24];
  const canaisPorTipo = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };
  return {
    width: b.readUInt32BE(16),
    height: b.readUInt32BE(20),
    bitDepth,
    colorType,
    temAlpha: colorType === 4 || colorType === 6,
    bitsTotal: bitDepth * (canaisPorTipo[colorType] ?? 1),
    bytes: b.length,
  };
}

/* ── 1. ASSETS DE LOJA ──────────────────────────────────────────── */
function checarAsset(nome, spec) {
  const caminho = join(ROOT, spec.arquivo);
  if (!existsSync(caminho)) { warn(`${nome}: ainda não existe (${spec.arquivo})`); return; }

  const png = lerPNG(caminho);
  if (!png) { err(`${nome}: não é um PNG válido`); return; }

  if (png.width !== spec.width || png.height !== spec.height)
    err(`${nome}: dimensão ${png.width}×${png.height}, esperado ${spec.width}×${spec.height} — a Play Store REJEITA`);
  else pass(`${nome}: dimensão ${png.width}×${png.height}`);

  if (spec.alpha === true && !png.temAlpha)
    err(`${nome}: EXIGE canal alpha (32-bit PNG). Encontrado ${png.bitsTotal}-bit sem alpha.`);
  if (spec.alpha === false && png.temAlpha)
    err(`${nome}: PROÍBE alpha. Transparência é rejeitada pela Play Store. Exporte 24-bit sem alpha.`);
  if (spec.alpha !== undefined && ((spec.alpha && png.temAlpha) || (!spec.alpha && !png.temAlpha)))
    pass(`${nome}: canal alpha correto (${png.temAlpha ? "com" : "sem"} alpha)`);

  if (spec.maxBytes && png.bytes > spec.maxBytes)
    err(`${nome}: ${(png.bytes/1024).toFixed(0)}KB excede o limite de ${(spec.maxBytes/1024).toFixed(0)}KB`);
}

checarAsset("Ícone da loja", TOKENS.storeAssets.icon);
checarAsset("Feature graphic", TOKENS.storeAssets.featureGraphic);

/* screenshots */
const ssDir = join(ROOT, TOKENS.storeAssets.screenshots.pasta);
if (existsSync(ssDir)) {
  const ss = TOKENS.storeAssets.screenshots;
  for (const loc of ss.locales) {
    const dir = join(ssDir, loc);
    if (!existsSync(dir)) { warn(`Screenshots: falta locale ${loc}`); continue; }
    const imgs = readdirSync(dir).filter(f => [".png",".jpg",".jpeg"].includes(extname(f).toLowerCase()));
    // 0 imagens = ainda não começou (pendência). 1 = começou e está incompleto (erro).
    if (imgs.length === 0) { warn(`Screenshots ${loc}: nenhuma imagem ainda`); continue; }
    if (imgs.length < ss.minCount) err(`Screenshots ${loc}: ${imgs.length} imagens, mínimo ${ss.minCount} para publicar`);
    if (imgs.length > ss.maxCount) err(`Screenshots ${loc}: ${imgs.length} imagens, máximo ${ss.maxCount}`);
    for (const f of imgs) {
      if (extname(f).toLowerCase() !== ".png") continue;
      const p = lerPNG(join(dir, f)); if (!p) continue;
      const ar = Math.max(p.width,p.height) / Math.min(p.width,p.height);
      if (ar > ss.maxAspectRatio) err(`Screenshot ${loc}/${f}: proporção ${ar.toFixed(2)}:1 excede ${ss.maxAspectRatio}:1`);
      if (Math.min(p.width,p.height) < ss.minSide) err(`Screenshot ${loc}/${f}: lado menor ${Math.min(p.width,p.height)}px < ${ss.minSide}px`);
      if (Math.max(p.width,p.height) > ss.maxSide) err(`Screenshot ${loc}/${f}: lado maior ${Math.max(p.width,p.height)}px > ${ss.maxSide}px`);
      if (p.temAlpha) err(`Screenshot ${loc}/${f}: tem alpha — a Play Store rejeita`);
    }
    if (imgs.length >= ss.minCount) pass(`Screenshots ${loc}: ${imgs.length} arquivos`);
  }
} else warn("Screenshots: pasta ainda não existe");

/* ── 2. TÍTULO E TEXTOS DA LOJA ─────────────────────────────────── */
const listing = join(ROOT, "store/listing.json");
if (existsSync(listing)) {
  const L = JSON.parse(readFileSync(listing, "utf8"));
  const proibidas = ["grátis","gratis","free","novo!","new!","#1","melhor jogo","best game","top 1"];
  for (const [loc, d] of Object.entries(L)) {
    if (d.title && d.title.length > TOKENS.storeAssets.title.maxChars)
      err(`Título ${loc}: ${d.title.length} caracteres, máximo ${TOKENS.storeAssets.title.maxChars}`);
    if (d.shortDescription && d.shortDescription.length > TOKENS.storeAssets.shortDescription.maxChars)
      err(`Descrição curta ${loc}: ${d.shortDescription.length} caracteres, máximo ${TOKENS.storeAssets.shortDescription.maxChars}`);
    const t = (d.title ?? "").toLowerCase();
    for (const p of proibidas) if (t.includes(p)) err(`Título ${loc}: contém termo promocional proibido "${p}"`);
  }
  pass(`Textos de loja: ${Object.keys(L).length} locales checados`);
} else warn("store/listing.json ainda não existe");

/* ── 3. CORES HARDCODED NO CÓDIGO (a alucinação mais comum) ─────── */
const permitidos = new Set();
(function coletar(o) {
  for (const v of Object.values(o)) {
    if (v && typeof v === "object") { if (typeof v.hex === "string") permitidos.add(v.hex.toUpperCase()); coletar(v); }
  }
})(TOKENS.color);

const IGNORAR = new Set(["node_modules",".git","dist","build","generated","Library","Temp","obj",".next"]);
const EXTS = new Set([".ts",".tsx",".js",".jsx",".cs",".css",".scss",".uss"]);
const achados = new Map();

function varrer(dir, prof = 0) {
  if (prof > 8 || !existsSync(dir)) return;
  for (const e of readdirSync(dir)) {
    if (IGNORAR.has(e) || e.startsWith(".")) continue;
    const p = join(dir, e);
    let st; try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) { varrer(p, prof + 1); continue; }
    if (!EXTS.has(extname(e))) continue;
    const txt = readFileSync(p, "utf8");
    for (const m of txt.matchAll(/#([0-9a-fA-F]{6})\b/g)) {
      const hex = ("#" + m[1]).toUpperCase();
      if (permitidos.has(hex)) continue;
      if (/^#(000000|FFFFFF)$/.test(hex)) continue;   // preto/branco puros em máscara são aceitáveis
      if (!achados.has(hex)) achados.set(hex, []);
      achados.get(hex).push(p.replace(ROOT + "/", ""));
    }
  }
}
varrer(ROOT);

if (achados.size) {
  err(`${achados.size} cor(es) fora dos tokens — provável alucinação da IA:`);
  for (const [hex, fs] of [...achados].slice(0, 12))
    erros.push(`      ${hex}  em ${fs.slice(0,2).join(", ")}${fs.length>2?` (+${fs.length-2})`:""}`);
} else pass(`Cores: nenhum hex fora dos ${permitidos.size} tokens aprovados`);

/* ── 4. CONTRASTE WCAG AA ───────────────────────────────────────── */
const lum = (hex) => {
  const c = [1,3,5].map(i => { const v = parseInt(hex.slice(i,i+2),16)/255; return v<=0.03928 ? v/12.92 : ((v+0.055)/1.055)**2.4; });
  return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2];
};
const ratio = (a,b) => { const [x,y]=[lum(a),lum(b)].sort((p,q)=>q-p); return (x+0.05)/(y+0.05); };

const fundo = TOKENS.color.surface.void.hex;
for (const [nome, tok] of Object.entries(TOKENS.color.text)) {
  if (nome === "onEmber") continue;
  const r = ratio(tok.hex, fundo);
  const min = nome === "muted" ? 3.0 : 4.5;
  if (r < min) err(`Contraste ${nome} (${tok.hex}) sobre void: ${r.toFixed(1)}:1 — mínimo WCAG ${min}:1`);
  else pass(`Contraste ${nome}: ${r.toFixed(1)}:1`);
}
const rEmber = ratio(TOKENS.color.text.onEmber.hex, TOKENS.color.brand.ember.hex);
if (rEmber < 4.5) err(`Contraste onEmber sobre ember: ${rEmber.toFixed(1)}:1 — mínimo 4.5:1`);
else pass(`Contraste onEmber sobre ember: ${rEmber.toFixed(1)}:1`);

/* ── 5. ESCALA TIPOGRÁFICA ──────────────────────────────────────── */
for (const [nome, s] of Object.entries(TOKENS.typography.scale)) {
  if (nome.startsWith("_")) continue;
  if (s.px < 12) err(`Tipografia "${nome}": ${s.px}px abaixo do mínimo legível de 12px`);
}
pass("Escala tipográfica: nenhum tamanho abaixo de 12px");

/* ── RELATÓRIO ──────────────────────────────────────────────────── */
console.log("\n\x1b[1m  VALIDAÇÃO DE MARCA — Rise After Dawn\x1b[0m\n");
for (const m of ok)     console.log(`  \x1b[32m✓\x1b[0m ${m}`);
for (const m of avisos) console.log(`  \x1b[33m•\x1b[0m ${m}`);
if (erros.length) {
  console.log("");
  for (const m of erros) console.log(`  \x1b[31m✗\x1b[0m ${m}`);
  console.log(`\n\x1b[31m\x1b[1m  BUILD REPROVADO — ${erros.length} violação(ões)\x1b[0m\n`);
  process.exit(1);
}
console.log(`\n\x1b[32m\x1b[1m  APROVADO\x1b[0m — ${ok.length} checagens, ${avisos.length} pendência(s)\n`);
