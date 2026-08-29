#!/usr/bin/env node
/**
 * balance-sim.mjs — Simulador de balanceamento de combate
 * Valida as fórmulas ANTES de virarem código de servidor.
 * Roda: node balance-sim.mjs
 */

// ── CURVA DE ATRIBUTOS ────────────────────────────────────────────
// +5 pontos livres por nível + 1 em todos os atributos base
const BASE = { STR: 10, AGI: 10, INT: 10, VIT: 10 };

function statsAtLevel(level, spec) {
  const auto = level - 1;                    // +1 em tudo por nível
  const free = (level - 1) * 5;              // 5 pontos livres
  const s = { STR: BASE.STR + auto, AGI: BASE.AGI + auto, INT: BASE.INT + auto, VIT: BASE.VIT + auto };
  // jogador distribui os livres conforme a especialização
  for (const [stat, pct] of Object.entries(spec)) s[stat] += Math.floor(free * pct);
  return s;
}

// ── DERIVADOS ─────────────────────────────────────────────────────
const derive = (s, level) => ({
  maxHp:       100 + s.VIT * 25 + level * 5,
  physDamage:  10 + s.STR * 2,
  magicDamage: 10 + s.INT * 2,
  armor:       s.STR * 1,
  critChance:  Math.min(0.05 + s.AGI * 0.0015, 0.75),   // teto 75%
  critMult:    1.5,
  atkSpeed:    1.0 + s.AGI * 0.005,
});

// ── MITIGAÇÃO ─────────────────────────────────────────────────────
// K = 50 + 15*nível. Curva suave, nunca chega a 100%, nunca negativa.
const mitigation = (armor, attackerLevel) => {
  const K = 50 + 15 * attackerLevel;
  return Math.max(0, Math.min(armor / (armor + K), 0.75));   // teto 75%
};

// ── DANO ──────────────────────────────────────────────────────────
function damage({ base, skillMult, armor, attackerLevel, crit }) {
  const raw = base * skillMult;
  const afterArmor = raw * (1 - mitigation(armor, attackerLevel));
  return Math.max(1, Math.round(afterArmor * (crit ? 1.5 : 1)));
}

// ── MONSTROS ──────────────────────────────────────────────────────
// tier 1 = comum, 2 = elite, 3 = boss
const monsterHp   = (lvl, tier) => Math.round((80 + lvl * 45) * [1, 1, 8, 200][tier]);
const monsterDmg  = (lvl, tier) => Math.round((8 + lvl * 3.2) * [1, 1, 1.8, 3.2][tier]);
const monsterArm  = (lvl, tier) => Math.round(lvl * 2 * [1, 1, 1.5, 2.2][tier]);

// ── SIMULAÇÃO DE TTK (time to kill) ──────────────────────────────
function ttk(level, specName, spec, tier, primary) {
  const s = statsAtLevel(level, spec);
  const d = derive(s, level);
  const base = primary === "INT" ? d.magicDamage : d.physDamage;
  const hp = monsterHp(level, tier);
  const arm = monsterArm(level, tier);
  // dano médio por segundo: ataque básico + rotação de skills (mult médio 1.9)
  const avgHit = damage({ base, skillMult: 1.9, armor: arm, attackerLevel: level, crit: false });
  const critBonus = 1 + d.critChance * (d.critMult - 1);
  const dps = avgHit * d.atkSpeed * critBonus;
  return { ttk: hp / dps, dps: Math.round(dps), hp, ehp: Math.round(d.maxHp / (1 - mitigation(d.armor, level))) };
}

// ── ESPECIALIZAÇÕES (distribuição de pontos livres) ───────────────
const SPECS = {
  "Guardian   (tank)":   { spec: { VIT: 0.7, STR: 0.3 }, primary: "STR" },
  "Ravager    (bruiser)":{ spec: { STR: 0.7, VIT: 0.3 }, primary: "STR" },
  "Pyromancer (dps mag)":{ spec: { INT: 0.8, VIT: 0.2 }, primary: "INT" },
  "Cryomancer (control)":{ spec: { INT: 0.7, VIT: 0.3 }, primary: "INT" },
  "Marksman   (dps fis)":{ spec: { AGI: 0.6, STR: 0.4 }, primary: "STR" },
  "Bladedancer(melee)":  { spec: { AGI: 0.7, STR: 0.3 }, primary: "STR" },
  "Lightbearer(heal)":   { spec: { INT: 0.5, VIT: 0.5 }, primary: "INT" },
  "Soulbinder (dot)":    { spec: { INT: 0.7, VIT: 0.3 }, primary: "INT" },
};

console.log("\n═══ TTK CONTRA MONSTRO COMUM (alvo: 2–5 s) ═══\n");
console.log("Especialização           Nv10    Nv20    Nv30    Nv40    Nv50    Nv60");
for (const [name, cfg] of Object.entries(SPECS)) {
  const row = [10, 20, 30, 40, 50, 60].map(l => ttk(l, name, cfg.spec, 1, cfg.primary).ttk.toFixed(1) + "s");
  console.log(name.padEnd(24) + row.map(r => r.padStart(7)).join(" "));
}

console.log("\n═══ TTK CONTRA BOSS — tempo COM GRUPO (alvo: 90–300 s) ═══\n");
console.log("Especialização           Nv20    Nv40    Nv60");
for (const [name, cfg] of Object.entries(SPECS)) {
  const row = [20, 40, 60].map(l => Math.round(ttk(l, name, cfg.spec, 3, cfg.primary).ttk / 2.5) + "s");
  console.log(name.padEnd(24) + row.map(r => r.padStart(7)).join(" "));
}

console.log("\n═══ SOBREVIVÊNCIA: EHP e hits até morrer (monstro comum) ═══\n");
console.log("Especialização           Nv30 EHP   hits    Nv60 EHP   hits");
for (const [name, cfg] of Object.entries(SPECS)) {
  const out = [30, 60].map(l => {
    const r = ttk(l, name, cfg.spec, 1, cfg.primary);
    const hits = Math.round(r.ehp / monsterDmg(l, 1));
    return `${String(r.ehp).padStart(8)} ${String(hits).padStart(6)}`;
  });
  console.log(name.padEnd(24) + out.join("  "));
}

console.log("\n═══ SANIDADE DA MITIGAÇÃO ═══\n");
console.log("Armadura   Nv10     Nv30     Nv60");
for (const a of [0, 30, 60, 120, 240, 500, 1000]) {
  const r = [10, 30, 60].map(l => (mitigation(a, l) * 100).toFixed(1) + "%");
  console.log(String(a).padEnd(11) + r.map(x => x.padStart(7)).join("  "));
}

// ── VERIFICAÇÕES AUTOMÁTICAS ──────────────────────────────────────
console.log("\n═══ VERIFICAÇÕES ═══\n");
let fail = 0;
const check = (cond, msg) => { console.log(`  ${cond ? "✓" : "✗"} ${msg}`); if (!cond) fail++; };

const dpsSpecs = ["Pyromancer (dps mag)", "Marksman   (dps fis)", "Bladedancer(melee)"];
const commonTtk = dpsSpecs.flatMap(n => [10,30,60].map(l => ttk(l, n, SPECS[n].spec, 1, SPECS[n].primary).ttk));
check(Math.max(...commonTtk) < 6, `DPS mata comum em <6s em todos os níveis (max ${Math.max(...commonTtk).toFixed(1)}s)`);
check(Math.min(...commonTtk) > 0.8, `Comum não morre num hit (min ${Math.min(...commonTtk).toFixed(1)}s)`);

const tank = ttk(60, "t", SPECS["Guardian   (tank)"].spec, 1, "STR");
const dps  = ttk(60, "d", SPECS["Pyromancer (dps mag)"].spec, 1, "INT");
check(tank.ehp > dps.ehp * 1.6, `Tank tem >1.6x o EHP do DPS (${(tank.ehp/dps.ehp).toFixed(2)}x)`);
check(dps.dps > tank.dps * 1.4, `DPS causa >1.4x o dano do tank (${(dps.dps/tank.dps).toFixed(2)}x)`);

check(mitigation(1e9, 60) <= 0.75, "Mitigação nunca passa de 75% mesmo com armadura absurda");
check(mitigation(0, 60) === 0, "Armadura 0 = mitigação 0");

const critMax = derive(statsAtLevel(60, { AGI: 1.0 }), 60).critChance;
check(critMax <= 0.75, `Crítico com AGI máxima não passa de 75% (${(critMax*100).toFixed(0)}%)`);

// grupo real: 1 tank + 1 healer + 2 dps ≈ 2.5x o DPS de um solo (não 4x)
const PARTY = 2.5;
for (const l of [20, 40, 60]) {
  const b = ttk(l, "b", SPECS["Marksman   (dps fis)"].spec, 3, "STR").ttk / PARTY;
  check(b > 90 && b < 300, `Boss nv${l} com grupo dura 1.5–5 min (${Math.round(b)}s)`);
}
const elite = ttk(40, "e", SPECS["Marksman   (dps fis)"].spec, 2, "STR").ttk;
check(elite > 8 && elite < 30, `Elite solo dura 8–30s (${elite.toFixed(1)}s)`);

console.log(fail ? `\n  ${fail} VERIFICAÇÃO(ÕES) FALHOU — ajustar constantes\n` : "\n  TODAS AS VERIFICAÇÕES PASSARAM\n");
process.exit(fail ? 1 : 0);
