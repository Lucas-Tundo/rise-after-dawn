# RISE AFTER DAWN — Arquitetura Completa

> **ARQUIVO MESTRE.** Tudo que este projeto precisa está aqui dentro.
> **Validado por execução real em 20/08/2026** — não é teoria.
>
> **Arquivos de código que acompanham (não são documentação, são executáveis):**
> - `prisma/schema.prisma` — 33 tabelas, 20 enums, validado no Prisma CLI 7.9.1
> - `design-tokens.json` — fonte única de cor, tipografia, espaçamento
> - `scripts/validate-brand.mjs` — quebra o build se a marca for violada
> - `scripts/balance-sim.mjs` — valida as fórmulas de combate, 11 verificações

---

## 🗺️ ÍNDICE

| Parte | Conteúdo | Quando ler |
|---|---|---|
| **[A] EXECUÇÃO** | Armadilhas, versões travadas, configs, tarefas com aceite | **Antes de escrever qualquer código** |
| **[B] ARQUITETURA** | Rede, i18n, arte, backend, custos, cronograma | Ao projetar um sistema |
| **[C] SISTEMAS DE JOGO** | Os 20 sistemas, o que copiar, o que melhorar | Ao implementar gameplay |
| **[D] PERSONAGEM** | Ficha estendida de David | Ao escrever conteúdo |
| **[E] LORE · HERÓIS · MONETIZAÇÃO** | Mundo, heróis, P2W, idioma | Ao definir economia e narrativa |
| **[F] COMBATE · CLASSES · BESTIÁRIO** | Especializações, fórmulas validadas, skills, monstros | **Ao implementar gameplay** |

---

## ⚡ RESUMO DE 60 SEGUNDOS

**O jogo:** ARPG isométrico hack'n'slash mobile, dungeons co-op de 4 jogadores, servidor autoritativo.
**Mercado:** Brasil primeiro, depois AR/CL/CO/PE, depois NA. **Idioma padrão: pt-BR.**
**Modelo:** F2P com P2W — pagante avança 3–5× mais rápido, F2P consegue tudo (ver Parte E5).
**Heróis:** 4 classes base × 2 especializações (nv20) = 8. **David** = Warrior → Guardian, gratuito.
**Combate:** fórmulas validadas em simulação — 11 verificações passando (`balance-sim.mjs`).
**Stack:** Unity 6 URP · NestJS 11.2.1 + Fastify 5.12.1 · Colyseus **0.16.5** · Prisma 7.9.1 · Supabase (São Paulo) · Redis 7.

**As 5 coisas que mais quebram este projeto, em ordem:**
1. Netcode ruim → a Etapa T8 é portão de risco, faça primeiro
2. Colyseus 0.17 (cliente só existe até 0.16.22) → **trave em 0.16.5**
3. NestJS e Colyseus exigem decorators incompatíveis → projetos e tsconfig separados
4. Migration no pooler 6543 do Supabase → **trava sem erro**, use 5432
5. Escopo crescendo → PvP é v2.0, não lançamento

---

# PARTE A — EXECUÇÃO

> **Este arquivo é para a IA (Cursor / Claude Code), não para humano ler de ponta a ponta.**
> Visão e arquitetura: a Parte B · Sistemas de jogo: a Parte C · Marca: `design-tokens.json`
> Este aqui é o **como executar**.
>
> **Validado em ambiente real em 20/08/2026** — Node 22.22.2, npm 10.9.7, PostgreSQL 16.2.
> Migration aplicada, 33 tabelas criadas, 20 enums, transação atômica testada,
> 4 clientes Colyseus conectados na mesma sala, anti-speedhack confirmado bloqueando.

---

## ⛔ LEIA ANTES DE QUALQUER COISA — AS 8 ARMADILHAS JÁ DESCOBERTAS

Estas falhas foram encontradas **executando de verdade**, não teorizando. Cada uma custaria de horas a semanas.

### 1. Colyseus 0.17 NÃO funciona — trave em 0.16.5

O servidor Colyseus está em 0.17.10, mas o **cliente parou em 0.16.22**. O SDK não acompanhou o servidor.

```
Servidor 0.17.10 + cliente 0.16.22  →  ❌ TypeError: Cannot read properties
                                          of undefined (reading 'name')
                                          em Client.consumeSeatReservation
Servidor 0.16.5  + cliente 0.16.22  →  ✅ JOIN OK
```

Testado com join único e sequencial para descartar corrida — é **incompatibilidade de protocolo real**. Nunca rode `npm update` no Colyseus. Trave as versões.

### 2. NestJS e Colyseus exigem modos de decorator INCOMPATÍVEIS

Esta é a mais perigosa porque o erro aparece longe da causa.

| | NestJS 11 | @colyseus/schema 3.x |
|---|---|---|
| Precisa de | `experimentalDecorators: true` | `Symbol.metadata` definido |
| Sem isso | `TypeError` em `request-mapping.decorator.js:15` | `TypeError: Cannot read properties of undefined (reading 'Symbol(Symbol.metadata)')` **na hora de serializar**, não na hora de decorar |

**Solução comprovada:** projetos separados, `tsconfig.json` separado, e **no realtime-server o polyfill é obrigatório na primeira linha do entrypoint**:

```typescript
(Symbol as any).metadata ??= Symbol.for("Symbol.metadata");
```

Sem essa linha, o servidor sobe, os clientes conectam, e só quebra quando tenta enviar o primeiro estado. Você perderia um dia inteiro procurando no lugar errado.

### 3. Supabase: migration NÃO funciona no pooler de transação (porta 6543)

`prisma migrate` executa internamente `SET session_replication_role = 'replica'`, que **não existe em modo transaction**. O comando não dá erro claro — ele **trava**. Ou retorna `prepared statement "s0" does not exist`.

Some a isso: **`directUrl` foi deprecado no Prisma 7**. O fluxo de duas URLs do Supabase mudou de lugar:

| | Onde configurar | Porta | Para quê |
|---|---|---|---|
| `DIRECT_URL` | `prisma.config.ts` | **5432** direta | migration, generate, CLI |
| `DATABASE_URL` | construtor `PrismaPg` | **6543** pooler | runtime da aplicação |

Validado em execução: a CLI leu `DIRECT_URL` e respondeu *Database schema is up to date*; o runtime conectou por `DATABASE_URL` na mesma operação.

### 4. Prisma 7.9+ rejeita `url` no bloco `datasource`

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")   // ❌ erro P1012, nem valida
}
```
A connection string vive **só** no `prisma.config.ts`. Praticamente todo tutorial na internet ainda ensina errado.

### 5. `@colyseus/ws-transport` não aceita `port` se você usa `listen()`

```typescript
new WebSocketTransport({ port: 2567 })   // ❌ "One and only one of port, server, or noServer"
new WebSocketTransport()                 // ✅ a porta vai no gameServer.listen(2567)
```

### 6. Colyseus 0.16 tem deps transitivas que o npm não instala sozinho

`@colyseus/redis-presence` e `@colyseus/redis-driver` são importados pelo `build/index.mjs` mas não vêm automaticamente → `ERR_MODULE_NOT_FOUND` no boot. Instale explicitamente.

### 7. Arquivo fora do `include` do tsconfig = decorators não se aplicam

Descoberto empacotando o projeto. Se um arquivo com `@type` do Colyseus estiver **fora** do padrão `include` do `tsconfig.json`, o TypeScript não aplica `experimentalDecorators` nele — e você recebe:

```
TypeError: Cannot read properties of undefined (reading 'constructor')
    at @colyseus/schema/src/annotations.ts:282
```

O erro aponta para dentro da biblioteca, então você procura no lugar errado. **Todo arquivo com Schema tem que estar sob `src/`** (ou ajuste o `include`).

### 8. BigInt quebra `JSON.stringify` — confirmado em execução

Sem o polyfill, qualquer rota que retorne ouro/gemas lança `TypeError`. Com ele, o valor sai como **string** (`{"gold":"500"}`), então o C# faz `long.Parse()`.

---

## 📌 MATRIZ DE VERSÕES — COPIE EXATAMENTE

Todas instaladas e executadas com sucesso juntas. **Use `--save-exact`. Não use `^`.**

### `/game-server` (NestJS + Prisma)
```
@nestjs/core@11.2.1              @nestjs/common@11.2.1
@nestjs/platform-fastify@11.2.1  @nestjs/config@4.0.4
@nestjs/jwt@11.0.2               fastify@5.12.1
prisma@7.9.1                     @prisma/client@7.9.1
@prisma/adapter-pg@7.9.1         pg@8.23.0
zod@4.4.3                        argon2@0.45.1
ioredis@6.0.0                    bullmq@6.1.2
reflect-metadata  rxjs  dotenv   [dev] tsx@4.23.12  typescript  @types/node
```

### `/realtime-server` (Colyseus)
```
colyseus@0.16.5                  @colyseus/core@0.16.5
@colyseus/schema@3.0.42          @colyseus/ws-transport@0.16.5
@colyseus/redis-presence         @colyseus/redis-driver
colyseus.js@0.16.22              [dev] tsx@4.23.12  typescript  @types/node
```
Instale com `--legacy-peer-deps` — a árvore do 0.16 tem conflito de peer que trava o npm sem isso.

### `/game-client` (Unity)
```
Unity 6 LTS · URP
com.unity.localization          (i18n, Smart Strings/ICU)
com.unity.addressables          (conteúdo + StringTables por locale)
Colyseus Unity SDK 0.16.x       ⚠️ TEM que ser 0.16.x, ver armadilha nº 1
```

---

## 📁 ESTRUTURA DE DIRETÓRIOS

```
rise-after-dawn/
├── ARCHITECTURE.md              ← este arquivo (Partes A–E)
├── docker-compose.yml           ← postgres + redis local
│
├── game-server/                 # NestJS · REST · Prisma  (porta 3000)
│   ├── package.json             # "type": "module"
│   ├── tsconfig.json            # experimentalDecorators: TRUE
│   ├── prisma.config.ts         # DATABASE_URL vive aqui
│   ├── prisma/
│   │   ├── schema.prisma
│   │   ├── migrations/
│   │   └── seed.ts
│   └── src/
│       ├── main.ts              # polyfill BigInt aqui
│       ├── generated/prisma/    # gerado, NÃO commitar
│       └── modules/{auth,character,inventory,economy,guild,liveops}/
│
├── realtime-server/             # Colyseus · WS         (porta 2567)
│   ├── package.json             # "type": "module"
│   ├── tsconfig.json            # experimentalDecorators: TRUE + useDefineForClassFields: FALSE
│   └── src/
│       ├── index.ts             # polyfill Symbol.metadata na LINHA 1
│       ├── rooms/{DungeonRoom,VillageRoom,SpireRoom}.ts
│       └── schema/{Player,DungeonState}.ts
│
├── web-portal/                  # Next.js               (porta 3002)
│   └── app/api/webhooks/[provider]/route.ts
│
├── content/                     # dados de jogo (fonte da verdade)
│   ├── source/{items,skills,monsters,quests}.csv
│   ├── translated/*.{es-419,en-US}.csv
│   └── build-locales.ts
│
└── game-client/                 # Unity 6
```

---

## ⚙️ ARQUIVOS DE CONFIGURAÇÃO — CONTEÚDO EXATO

### `game-server/tsconfig.json` — validado com NestJS 11
```json
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "bundler",
    "target": "ES2023",
    "lib": ["ES2023"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "outDir": "dist"
  },
  "include": ["src/**/*.ts", "*.ts"]
}
```

### `realtime-server/tsconfig.json` — validado com Colyseus 0.16.5
```json
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "bundler",
    "target": "ES2022",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "useDefineForClassFields": false,
    "outDir": "dist"
  },
  "include": ["src/**/*.ts", "*.ts"]
}
```
> `useDefineForClassFields: false` é **obrigatório**. Com `true`, os campos da classe sobrescrevem o que o decorator `@type` registrou e a serialização retorna lixo.

### `game-server/prisma.config.ts`
```typescript
import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations", seed: "tsx prisma/seed.ts" },
  datasource: { url: env("DATABASE_URL") },
});
```

### `docker-compose.yml`
```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: rad
      POSTGRES_PASSWORD: rad_dev_only
      POSTGRES_DB: rad
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U rad"]
      interval: 5s
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
volumes: { pgdata: }
```

### `game-server/.env`
```
DATABASE_URL="postgresql://rad:rad_dev_only@localhost:5432/rad?schema=public"
REDIS_URL="redis://localhost:6379"
JWT_SECRET="troque-isto-em-producao"
JWT_ACCESS_TTL="15m"
JWT_REFRESH_TTL="30d"
```

---

## 🔌 PADRÕES OBRIGATÓRIOS — CÓDIGO TESTADO

### Prisma Client (validado escrevendo em Postgres real)
```typescript
// game-server/src/prisma.ts
import "dotenv/config";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "./generated/prisma/client.js";  // .js OBRIGATÓRIO em ESM

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL! });
export const prisma = new PrismaClient({ adapter });
```

### Polyfill BigInt — `main.ts`, antes do bootstrap
```typescript
(BigInt.prototype as any).toJSON = function () { return this.toString(); };
```

### Transação atômica de economia — **validada, reconciliou 500n == 500n**

Toda operação de moeda usa exatamente este formato. Ledger e saldo na **mesma** transação.
```typescript
await prisma.$transaction(async (tx) => {
  await tx.economyLedger.create({
    data: {
      characterId, currency: "GOLD", amount: 500n, balanceAfter: novoSaldo,
      operation: "DUNGEON_REWARD", referenceId: runId,
    },
  });
  await tx.walletBalance.update({
    where: { characterId_currency: { characterId, currency: "GOLD" } },
    data: { amount: { increment: 500n } },
  });
});
```
**Job noturno de reconciliação:** `SUM(EconomyLedger.amount) === WalletBalance.amount`. Divergir = exploit. Alerta imediato.

### Sala Colyseus — validada com 4 clientes reais
```typescript
// realtime-server/src/index.ts
(Symbol as any).metadata ??= Symbol.for("Symbol.metadata");  // ← LINHA 1, SEMPRE

import { Server, Room, Client } from "colyseus";
import { Schema, MapSchema, type } from "@colyseus/schema";
import { WebSocketTransport } from "@colyseus/ws-transport";

const TICK_HZ = 20;
const TICK_MS = 1000 / TICK_HZ;
const MAX_SPEED = 6.0;      // m/s
const TOLERANCE = 1.15;     // margem para jitter de rede

class Player extends Schema {
  @type("string") characterId = "";
  @type("float32") x = 0;
  @type("float32") z = 0;
  @type("uint32") lastSeq = 0;
  @type("int32") hp = 100;
}
class DungeonState extends Schema {
  @type({ map: Player }) players = new MapSchema<Player>();
  @type("uint32") tick = 0;
}

class DungeonRoom extends Room<DungeonState> {
  maxClients = 4;

  onCreate() {
    this.state = new DungeonState();
    this.setSimulationInterval(() => { this.state.tick++; }, TICK_MS);

    this.onMessage("input", (client, msg: { seq: number; x: number; z: number; dt: number }) => {
      const p = this.state.players.get(client.sessionId);
      if (!p) return;
      if (msg.seq <= p.lastSeq) return;                        // anti-replay
      const dist = Math.hypot(msg.x - p.x, msg.z - p.z);
      if (dist > MAX_SPEED * msg.dt * TOLERANCE) {             // ANTI-SPEEDHACK
        client.send("correction", { seq: msg.seq, x: p.x, z: p.z });
        return;                                                // descarta o input
      }
      p.x = msg.x; p.z = msg.z; p.lastSeq = msg.seq;
    });
  }
  onJoin(client: Client, opts: { characterId: string }) {
    const p = new Player(); p.characterId = opts.characterId;
    this.state.players.set(client.sessionId, p);
  }
  onLeave(client: Client) { this.state.players.delete(client.sessionId); }
}

const gameServer = new Server({ transport: new WebSocketTransport() });  // SEM port aqui
gameServer.define("dungeon", DungeonRoom);
await gameServer.listen(2567);
```
**Resultado do teste real:** cliente pediu `x: 500` (teleporte); posição autoritativa ficou em `x: 1.00` e o `correction` foi entregue. O anti-cheat funciona.

---

---

## 🗄️ SUPABASE — CONFIGURAÇÃO CANÔNICA

O banco deste projeto é **Supabase (PostgreSQL gerenciado)**. Padrão validado em execução real.

### ⚠️ DECISÃO IRREVERSÍVEL: escolha a região na criação

**A região de um projeto Supabase NÃO pode ser alterada depois.** O projeto fica preso à infraestrutura física daquela região para sempre. Mudar exige criar projeto novo, migrar schema, dados, storage e trocar toda URL e chave.

```
✅ CORRETO:  South America (São Paulo) — sa-east-1
❌ ERRADO:   qualquer região dos EUA (é o padrão sugerido no formulário)
```

Se o servidor de jogo está em São Paulo e o banco em us-east-1, **toda query carrega +110 a 140 ms**. Num ARPG isso é a diferença entre login instantâneo e tela de carregamento. Confira duas vezes antes de clicar em criar.

### As três connection strings

O Dashboard oferece três. Use **duas**:

| Tipo | Formato | Uso neste projeto |
|---|---|---|
| **Direct** | `postgresql://postgres:SENHA@db.REF.supabase.co:5432/postgres` | ✅ `DIRECT_URL` — migrations |
| **Transaction pooler** | `postgresql://postgres.REF:SENHA@aws-0-sa-east-1.pooler.supabase.com:6543/postgres?pgbouncer=true` | ✅ `DATABASE_URL` — runtime |
| **Session pooler** | `...pooler.supabase.com:5432/postgres` | fallback se a rede não tiver IPv6 |

> A conexão direta é **IPv6-only**. Se seu VPS não tem IPv6, use o **session pooler (5432)** como `DIRECT_URL` — ele é IPv4 e aceita migrations. O que **nunca** funciona para migration é a porta **6543**.

### `.env`
```bash
DATABASE_URL="postgresql://postgres.REF:SENHA@aws-0-sa-east-1.pooler.supabase.com:6543/postgres?pgbouncer=true&connection_limit=10"
DIRECT_URL="postgresql://postgres:SENHA@db.REF.supabase.co:5432/postgres"
```

### `prisma.config.ts` — CLI usa a conexão direta
```typescript
import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations", seed: "tsx prisma/seed.ts" },
  datasource: { url: env("DIRECT_URL") },   // ← 5432. NUNCA 6543.
});
```

### `src/prisma.ts` — runtime usa o pooler
```typescript
import "dotenv/config";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "./generated/prisma/client.js";

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL! });
export const prisma = new PrismaClient({ adapter });
```

### Limite de conexões — a armadilha do multi-processo

O servidor de jogo roda **4 a 6 processos Node**, cada um com seu pool. Sem limite explícito, o Prisma abre `num_cpus * 2 + 1` por processo e estoura o pooler com `Max client connections reached`.

**Regra:** `connection_limit` na URL, e a soma de todos os processos deve caber no Pool Size do Supabase.
```
6 processos × connection_limit=10 = 60 conexões
→ Pool Size do Supabase precisa ser ≥ 60 (Settings → Database → Pool Size)
```

### Schema separado do PostgREST

Supabase expõe automaticamente o schema `public` como API REST. Suas tabelas de jogo **não devem ficar lá** — é superfície de ataque desnecessária.
```bash
DIRECT_URL="...postgres?schema=game"
```
Rode `CREATE SCHEMA IF NOT EXISTS game;` antes da primeira migration.

### Auth: use a sua, não a do Supabase

Mantenha Argon2id + JWT próprio (Etapa T5). Motivo: o Colyseus valida **o mesmo JWT** no `onAuth` da sala, e o token precisa carregar `characterId`, `shardId` e `protocolVersion` — coisas que o Supabase Auth não conhece. Misturar os dois cria duas fontes de verdade de sessão.

Consequência já documentada: como o Prisma conecta com service role, **RLS é ignorado**. A segurança vive nos guards do NestJS.

### 📊 CRESCIMENTO DO BANCO — MEDIDO, NÃO ESTIMADO

Inseri 10.000 linhas de `EconomyLedger` e 5.000 de `ItemInstance` num Postgres 16 real e medi com `pg_total_relation_size`:

| Tabela | Bytes por linha (com índices) |
|---|---|
| `EconomyLedger` | **395 B** |
| `ItemInstance` | **472 B** |

Um jogador ativo gera por dia: ~15 linhas de ledger (5,9 KB) + ~9 itens (4,2 KB) = **~10 KB/dia**.

**Autonomia do free tier (500 MB):**

| DAU | Crescimento/dia | 500 MB acabam em |
|---|---|---|
| 100 | 1 MB | ~16 meses |
| 500 | 5 MB | ~3 meses |
| 1.000 | 10 MB | **~7 semanas** |

> ⚠️ O `EconomyLedger` é **append-only** — nunca encolhe. Ele é o que enche o banco, não os jogadores.

**Estratégia de arquivamento (implementar na T1, não depois):**
1. Particione `EconomyLedger` por mês (`PARTITION BY RANGE (createdAt)`).
2. Job mensal exporta partições com mais de 90 dias para Cloudflare R2 em Parquet e dá `DROP` na partição.
3. `WalletBalance` continua sendo o saldo vivo — o histórico frio sai da tabela quente sem perder auditoria.

Sem isso, você faz upgrade de plano por causa de log, não de jogadores.

### Free tier: o que realmente te pega

| Limite | Valor | Impacto real |
|---|---|---|
| **Pausa por inatividade** | **7 dias sem query** | ☠️ **O pior.** Projeto sai do ar até você religar manualmente (~30s). Em soft launch é fatal. |
| Banco | 500 MB | ver tabela acima |
| Egress | 5 GB/mês | ok para o jogo (payload é pequeno) |
| Projetos ativos | 2 | perfeito: 1 dev + 1 prod |
| Conexões realtime | 200 | **irrelevante** — você usa Colyseus, não Supabase Realtime |
| Backup | nenhum | ☠️ faça `pg_dump` seu, agendado |

**Mitigação da pausa durante desenvolvimento:** um cron a cada 3 dias fazendo `SELECT 1`. **Antes do soft launch: suba para Pro (US$ 25/mês).** Um projeto pausado no dia do lançamento não tem conserto de imagem.

### Checklist de aceite Supabase
- [ ] Projeto criado em **South America (São Paulo)** — conferir duas vezes
- [ ] `DIRECT_URL` na porta 5432, `DATABASE_URL` na 6543
- [ ] `prisma migrate dev` completa sem travar
- [ ] `connection_limit` definido e somado abaixo do Pool Size
- [ ] Schema `game`, não `public`
- [ ] `pg_dump` agendado
- [ ] Cron anti-pausa ativo (ou Pro contratado)
- [ ] Particionamento do `EconomyLedger` planejado

---

## 🎯 TAREFAS EXECUTÁVEIS

Formato: cada tarefa tem **comando**, **arquivos**, e **teste de aceite verificável**. Não avance sem o aceite passar.

---

### T0 — Fundação
```bash
mkdir rise-after-dawn && cd rise-after-dawn && git init
docker compose up -d
mkdir -p game-server/prisma realtime-server/src web-portal content/source
```
**Aceite:** `docker compose ps` mostra postgres e redis `healthy`.

---

### T1 — Banco de dados

```bash
cd game-server
npm init -y && npm pkg set type=module
npm i --save-exact prisma@7.9.1 @prisma/client@7.9.1 @prisma/adapter-pg@7.9.1 pg@8.23.0 dotenv
npm i -D --save-exact tsx@4.23.12 typescript @types/node
# copiar schema.prisma, prisma.config.ts, tsconfig.json, .env
npx prisma migrate dev --name init
npx prisma generate
```

**Aceite** (todos validados na execução real):
- [ ] `npx prisma migrate dev` termina sem erro
- [ ] `SELECT count(*) FROM information_schema.tables WHERE table_schema='public'` → **33**
- [ ] `SELECT count(*) FROM pg_type WHERE typtype='e'` → **20**
- [ ] `npx prisma generate` gera em `src/generated/prisma`
- [ ] Adicionar `src/generated/` ao `.gitignore`

---

### T2 — Smoke test de persistência

Crie `smoke.ts` que: cria User → cria Character com attributes e wallets aninhados → executa a transação atômica de 500 gold → compara `SUM(ledger)` com `WalletBalance`.

**Aceite** (saída literal esperada, já reproduzida):
```
char: Kaelen VANGUARD pts: 5
ledger SUM: 500n | wallet: 500n
RECONCILIADO: OK
BigInt->JSON: {"gold":"500"}
UNIQUE name bloqueou duplicata: OK
```
Se `RECONCILIADO` falhar, a transação não é atômica — **pare e conserte antes de seguir**.

---

### T3 — NestJS + endpoint `/bootstrap`

```bash
npm i --save-exact @nestjs/core@11.2.1 @nestjs/common@11.2.1 \
  @nestjs/platform-fastify@11.2.1 @nestjs/config@4.0.4 fastify@5.12.1 \
  reflect-metadata rxjs zod@4.4.3
```
`main.ts` importa `reflect-metadata` primeiro, aplica o polyfill BigInt, e usa `FastifyAdapter`.

**Aceite:**
```bash
curl localhost:3000/api/v1/bootstrap
# → {"minClientVersion":"1.0.0","protocolVersion":1,
#    "locales":["pt-BR","es-419","en-US"],"maintenance":{"active":false}}
```
Se der `TypeError` em `request-mapping.decorator.js` → falta `experimentalDecorators: true`.

---

### T4 — Colyseus (⚠️ tarefa de maior risco)

```bash
cd ../realtime-server && npm init -y && npm pkg set type=module
npm i --legacy-peer-deps --save-exact colyseus@0.16.5 @colyseus/core@0.16.5 \
  @colyseus/schema@3.0.42 @colyseus/ws-transport@0.16.5
npm i --legacy-peer-deps @colyseus/redis-presence @colyseus/redis-driver
npm i --legacy-peer-deps --save-exact colyseus.js@0.16.22
npm i -D --legacy-peer-deps --save-exact tsx@4.23.12 typescript @types/node
```

**Aceite** (todos reproduzidos na validação):
- [ ] Servidor sobe na 2567
- [ ] 4 clientes entram na **mesma** `roomId`
- [ ] `state.tick` incrementa (~20/s)
- [ ] `state.players.size === 4` **no cliente** (prova que a serialização funciona)
- [ ] Input com `x: 500` num tick → posição autoritativa não muda + `correction` recebido
- [ ] `gracefullyShutdown()` sem erro

**Se falhar com `Symbol(Symbol.metadata)`:** falta o polyfill na linha 1.
**Se falhar com `reading 'name'`:** versão errada de Colyseus — volte para 0.16.5.

---

### T5 — Auth (Argon2id + JWT rotativo)

Rotas: `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/guest`.
Guarde **hash** do refresh token, nunca o token. `replacedById` detecta reúso = sessão comprometida → revoga a cadeia toda.

**Aceite:** registrar → logar → refresh gera par novo → **reusar o refresh antigo é rejeitado e revoga a cadeia**.

---

### T6 — Pipeline de conteúdo e i18n

`content/build-locales.ts` lê os CSVs e gera seed do Postgres + StringTables da Unity.
**O build FALHA (exit 1)** se: chave faltando em algum locale, placeholder ICU sumindo, ou string >140% do tamanho do inglês.

**Aceite:** um item retorna nome correto nos 3 locales; remover uma chave de `es-419` quebra o build.

---

### T7 — Handshake Colyseus ↔ NestJS

`onAuth` da sala valida o **mesmo JWT** emitido pelo NestJS e rejeita `protocolVersion` divergente.

**Aceite:** token válido entra; token adulterado é rejeitado; protocolo diferente é rejeitado.

---

### T8 — Etapa 0 do blueprint (portão de risco)

Cliente Unity: cubo, joystick, **predição + reconciliação + interpolação**, overlay de debug com RTT/tick/taxa de reconciliação. Deploy do servidor em São Paulo.

**Aceite — este é o portão que decide o projeto:**
- [ ] 4 celulares reais em **4G** (não Wi-Fi), um deles tier LOW
- [ ] RTT p95 < 120 ms
- [ ] Reconciliação < 5% dos ticks
- [ ] O movimento **parece** instantâneo ao toque

❌ Reprovou → ajuste tick, taxa de broadcast ou payload **antes** de escrever qualquer sistema de jogo.

---

## 🧱 REGRAS INVIOLÁVEIS PARA A IA

1. **Nunca** `npm update` / `npm i pacote@latest`. Só as versões da matriz.
2. **Nunca** `prisma db push`. Sempre `prisma migrate dev`.
3. **Nunca** string de UI hardcoded. Sempre chave de localização.
4. **Nunca** `characterId` vindo de parâmetro do cliente — sempre derivado do JWT. Isso é IDOR.
5. **Nunca** moeda fora de `$transaction` com Ledger + WalletBalance juntos.
6. **Nunca** cálculo de dano, crítico, loot ou cooldown no cliente.
7. **Nunca** `new Date()` do cliente para lógica. Sempre hora do servidor.
8. **Nunca** nomes, assets, textos ou lore do jogo de referência. Sistemas sim (ver a Parte C), expressão não.
9. Todo import ESM de arquivo local termina em `.js`, mesmo escrevendo `.ts`.
10. Antes de dizer que uma tarefa está pronta, **rode o teste de aceite**.

---

## 🔍 TABELA DE DIAGNÓSTICO

| Erro | Causa | Correção |
|---|---|---|
| `P1012` datasource url | Sintaxe Prisma 6 | Remova `url` do `datasource` |
| `Cannot find module '.../generated/prisma/client'` | Falta gerar ou falta `.js` no import | `npx prisma generate` + sufixo `.js` |
| `Do not know how to serialize a BigInt` | Falta polyfill | `BigInt.prototype.toJSON` no `main.ts` |
| `TypeError` em `request-mapping.decorator.js` | Decorators desligados | `experimentalDecorators: true` |
| `reading 'Symbol(Symbol.metadata)'` na serialização | Falta polyfill do Colyseus | `Symbol.metadata ??=` na linha 1 |
| `reading 'name'` em `consumeSeatReservation` | Colyseus 0.17 vs cliente 0.16 | Servidor → 0.16.5 |
| `One and only one of port, server...` | Porta duplicada | `new WebSocketTransport()` sem args |
| `ERR_MODULE_NOT_FOUND @colyseus/redis-presence` | Dep transitiva ausente | Instale explicitamente |
| Estado sincroniza vazio/lixo | `useDefineForClassFields: true` | Ponha `false` |
| `ERESOLVE` instalando Colyseus | Conflito de peer 0.16 | `--legacy-peer-deps` |
| `reading 'constructor'` em annotations.ts | Arquivo Schema fora do `include` | Mova para `src/` |
| `prisma migrate` **trava sem erro** | Usando pooler 6543 | `DIRECT_URL` na porta 5432 |
| `prepared statement "s0" does not exist` | Migration no pooler de transação | idem acima |
| `Max client connections reached` | Soma dos pools > Pool Size | `connection_limit` na URL |
| `LengthMismatch` no insert | String excede `@db.VarChar(n)` | Valide com Zod **antes** do banco |
| Toda query com +120 ms | Supabase em região dos EUA | Recriar projeto em São Paulo |

---

## ✅ O QUE JÁ ESTÁ PROVADO E O QUE NÃO ESTÁ

**Validado executando de verdade:**
Migration em Postgres 16 real · 33 tabelas · 20 enums · Prisma Client conectando e escrevendo · transação atômica reconciliando · constraint de nome único bloqueando · polyfill BigInt · NestJS 11 + Fastify 5 respondendo HTTP 200 · Colyseus 0.16.5 com 4 clientes na mesma sala · tick 20 Hz · state sync chegando no cliente · anti-speedhack bloqueando teleporte · shutdown limpo.

Padrão de duas URLs do Supabase (CLI via `DIRECT_URL`, runtime via `DATABASE_URL`) · crescimento do banco medido em bytes reais por linha · constraint `VarChar(16)` bloqueando nome longo.

**Ainda NÃO validado (precisa do seu ambiente):**
Unity 6 + Colyseus SDK C# · predição e reconciliação no cliente · RTT real em 4G brasileiro · performance em aparelho tier LOW · webhook de pagamento com gateway real · Addressables + CDN.

> A **T8** é a que ainda pode derrubar a arquitetura. Todo o resto acima é chão firme.


---

# PARTE B — ARQUITETURA

> **Status:** Especificação Canônica Revisada · Substitui integralmente a v1.0
> **Gênero:** ARPG / MMO-lite mobile isométrico, hack 'n' slash, co-op 4 jogadores
> **Stack:** Unity 6 LTS (URP) · NestJS 11.2.1 + Fastify 5.12.1 · Colyseus 0.16.5 · Prisma 7.9.1 (Postgres 16) · Redis 7 · Next.js 16
> **⚙️ Execução:** ver a Parte A — versões travadas e validadas em ambiente real
> **Mercado primário:** América do Sul (BR · AR · CL · CO · PE) — **Expansão:** América do Norte (US · CA · MX)
> **Idiomas de lançamento:** `pt-BR` · `es-419` · `en-US`
> **Referência de gênero:** *Clash for Dawn: Guild War* (LEDO, 2015–2025) — **sucessor espiritual, NÃO remake**

---

---

## 0. CHANGELOG v1.0 → v2.0

| # | Problema na v1.0 | Correção na v2.0 |
|---|---|---|
| 1 | Schema Prisma com sintaxe v6 (quebra no boot) | Sintaxe v7: `prisma-client`, `output`, `@prisma/adapter-pg`, ESM, `prisma.config.ts` |
| 2 | `itemId String` sem tabela de item | `ItemDefinition` + `ItemInstance` + rolagem de afixos |
| 3 | RLS descrito como blindagem (não funciona via Prisma) | RLS removido como premissa; segurança na camada de aplicação + auditoria |
| 4 | `gold`/`diamonds` duplicados com Ledger | Ledger = verdade · `WalletBalance` = cache materializado na mesma transação |
| 5 | Socket.io cru sem orquestração de salas | **Colyseus** — salas autoritativas, matchmaking, SDK Unity oficial |
| 6 | Zero menção a tick / predição / reconciliação | Seção 5 inteira dedicada (é o risco nº 1 do projeto) |
| 7 | `proxy.ts` do Next.js (não existe) | Route Handler `app/api/webhooks/[provider]/route.ts` + HMAC no raw body |
| 8 | Sem i18n | Arquitetura i18n server-authoritative, 3 locales, Seção 4 |
| 9 | 3 classes (original tinha 8) | 4 no lançamento (com healer, essencial para co-op 4p) + 4 no roadmap |
| 10 | Sem guildas, quests, chat, mercado, mercenários, pets | Todos modelados no schema v2 |
| 11 | "PBR + volumétrico" vs celular básico | Direção de arte *stylized PBR* com budgets duros por tier de device |
| 12 | VRS/GPU Instancing com premissas erradas | Seção 6 corrigida (SRP Batcher x Instancing, VRS opcional) |
| 13 | `prisma db push` | `prisma migrate` desde o commit 1 |
| 14 | Monetização "sem taxa de 30%" | Realidade regulatória por loja/país, Seção 9 |
| 15 | Escopo de lançamento gigante | PvP massivo e World Boss movidos para pós-lançamento |

---

## 1. IDENTIDADE, IP E NAMING BIBLE

### 1.1 ⚠️ Aviso sobre o título

**`Rise After Dawn` tem risco moderado de colidir com `Clash for Dawn`.** Mesma classe de produto (jogo mobile), mesma estrutura de três palavras, mesmo substantivo final. A palavra "Dawn" sozinha não é protegível, mas a **similaridade confusória** é o critério que o INPI e o Google Play usam.

**Recomendação:** registre a marca no INPI (classe NCL 9 e 41) antes do soft launch — custa ~R$ 400 e leva de 12 a 24 meses. Enquanto isso, considere alternativas com risco menor:

| Alternativa | Domínio/handle | Observação |
|---|---|---|
| **Emberfall** | forte, curto | Funciona em PT/ES sem tradução |
| **Ashen Vigil** | forte | Casa com a lore proposta abaixo |
| **Broken Halo** | forte | Cuidado: "Halo" é marca da Microsoft em games ❌ |
| **Solhaven** | muito forte | Nome da cidade vira nome do jogo |
| **Rise After Dawn** | risco moderado | Escolha atual — viável, mas registre |

> **Decisão do projeto:** manter `Rise After Dawn` como codinome de desenvolvimento; decidir o título comercial definitivo antes da Etapa 7 (loja).

### 1.2 Naming Bible — mundo e lore (100% original, canônico em inglês)

Toda a lore abaixo é **nova**. Nenhum elemento vem de *Clash for Dawn*.

| Elemento | Nome canônico (EN) | pt-BR (exibição) | es-419 (exibição) |
|---|---|---|---|
| Mundo / continente | **Aurethia** | Aurethia | Aurethia |
| Cidade-bastião inicial | **Solhaven** | Solhaven | Solhaven |
| Ordem do jogador | **The Vigil** | A Vigília | La Vigilia |
| Antagonista principal | **The Hollow Crown** | A Coroa Oca | La Corona Hueca |
| Cataclismo fundador | **The Sundering** | A Ruptura | La Ruptura |
| Energia mágica do mundo | **Aether** | Éter | Éter |
| Corrupção / inimigos | **The Blight** | A Praga | La Plaga |

**Nomes próprios (Aurethia, Solhaven) NÃO são traduzidos** — só substantivos comuns e conceitos.

### 1.3 Facções PvP (substituem "Brotherhood vs Order")

| Facção | Nome canônico (EN) | Identidade | Cor |
|---|---|---|---|
| A | **Ironvow** | Ordem, disciplina, defesa dos vivos | Azul-aço / dourado |
| B | **Ashenfold** | Pragmatismo, magia de sangue, fim justifica meios | Carmim / cinza |

Alinhamento é escolhido no nível 15 e é permanente por personagem (troca paga, cooldown de 30 dias).

### 1.4 Classes

**Lançamento (4 classes)** — 4 é o mínimo para co-op de 4 jogadores funcionar (tank / healer / 2 DPS):

| Classe (EN) | Papel | Atributo primário | Recurso |
|---|---|---|---|
| **Vanguard** | Tank / controle de grupo | Vitality | Rage |
| **Arcanist** | DPS mágico em área | Intelligence | Aether |
| **Ranger** | DPS físico single-target, crítico | Agility | Focus |
| **Warden** | Suporte / cura / escudos | Intelligence + Vitality | Aether |

**Roadmap pós-lançamento:** `Reaver` (berserker), `Shadowblade` (assassino), `Templar` (paladino híbrido), `Beastcaller` (invocador).

> ⚠️ **Nota de escopo:** se o cronograma apertar, corte o **Warden** e lance com 3 classes + poções de cura mais fortes. É a decisão certa. Nunca corte o **Vanguard**.

### 1.5 Sistemas herdados do gênero (renomeados)

O *Clash for Dawn* tinha estes sistemas. **Mecânicas de jogo não são protegidas por direito autoral** — nomes, arte, texto e código são. Portanto: reimplemente livremente, renomeie sempre.

| Sistema original | Nome neste projeto | Fase |
|---|---|---|
| Mercenaries | **Companions** | v1.2 |
| Pets / Dragons | **Familiars** | v1.3 |
| Illusionary Palaces (24 andares) | **The Spire** (torre infinita) | v1.1 |
| Costumes | **Vanity** | v1.1 |
| Guild War | **Faction War** | v2.0 |
| Treasure Hunting | **Expeditions** | v1.2 |
| Collection Gallery | **Codex** | v1.2 |

### 1.6 🔒 Regra de ouro anti-infração

**PERMITIDO:** copiar mecânicas, loops de progressão, arquitetura de sistemas, sensação de combate, estrutura de UI (posição de joystick e botões é convenção do gênero).

**PROIBIDO — nunca faça, nem "temporariamente para testar":**
- Extrair, descompilar ou reutilizar qualquer asset do APK original (modelos, texturas, som, ícones, fontes, música).
- Usar os nomes `Luxis`, `Angeli`, `Brotherhood`, `The Order`, `Dark Lord`, `Chosen One`, `Clash for Dawn` — em código, em comentário, em nome de arquivo, em qualquer lugar.
- Descrever o jogo publicamente como "remake", "2.0", "continuação" ou "versão brasileira" de *Clash for Dawn*. Use: *"ARPG isométrico co-op inspirado nos clássicos do gênero"*.
- Usar arte de referência do original em material de marketing.

> Marketing como "o Clash for Dawn brasileiro" é o caminho mais rápido para um takedown na Google Play. A LEDO lançou um *Clash for Dawn 2* na Coreia — a marca está ativa e vigiada.

---

## 2. MERCADO, IDIOMAS E REGIÕES

### 2.1 Estratégia geográfica

```
FASE A (lançamento)   → Brasil               pt-BR          shard: sa-gru-1
FASE B (+3 meses)     → AR · CL · CO · PE    es-419         shard: sa-gru-1 (mesmo)
FASE C (+9 meses)     → US · CA · MX         en-US · es-419 shard: na-iad-1 (novo)
```

**Um shard único em São Paulo cobre toda a América do Sul.** Latências reais aproximadas a partir de GRU (São Paulo):

| Destino | RTT esperado | Jogável em ARPG? |
|---|---|---|
| São Paulo / Rio | 10–25 ms | ✅ excelente |
| Sul e Nordeste BR | 25–50 ms | ✅ ótimo |
| Buenos Aires | 30–45 ms | ✅ ótimo |
| Santiago | 40–60 ms | ✅ bom |
| Lima | 60–85 ms | ⚠️ aceitável com predição |
| Bogotá | 95–130 ms | ⚠️ precisa de predição robusta |
| Cidade do México | 130–180 ms | ❌ exige shard NA |

**Conclusão de engenharia:** a predição de cliente (Seção 5.2) não é enfeite — é o que torna Colômbia e Peru jogáveis. Sem ela, seu mercado endereçável cai para BR + Cone Sul.

### 2.2 Perfil de dispositivo — o que REALMENTE limita os gráficos

O aparelho mediano na América do Sul não é um flagship. Este é o alvo real:

| Tier | Aparelhos típicos | RAM | Meta de FPS | % do público SA |
|---|---|---|---|---|
| **LOW** | Moto G / Galaxy A0x / Redmi A | 3–4 GB | **30 fps travado** | ~45% |
| **MID** | Galaxy A5x / Redmi Note / Moto G Power | 6 GB | 45–60 fps | ~40% |
| **HIGH** | Galaxy S / iPhone 13+ / Poco F | 8 GB+ | 60 fps + efeitos | ~15% |

**Piso técnico obrigatório:** Android 10, OpenGL ES 3.1, ARM64, 3 GB RAM, 2 GB livres de armazenamento. iOS 15+.

> 💡 **A regra que vale ouro:** o jogo é desenvolvido **primeiro no tier LOW**. Um Moto G físico fica na sua mesa e roda o build toda semana. Se você desenvolver no editor de um PC e só testar no celular no final, o projeto morre no ajuste de performance.

### 2.3 Fusos horários e reset diário

América do Sul cruza UTC−3 até UTC−5. O Brasil **não tem mais horário de verão** (desde 2019), mas Chile e Paraguai têm.

**Decisão canônica:**
- Reset diário: **09:00 UTC** (= 06:00 BRT / 05:00 ART... espere, ART é UTC−3 = 06:00 / 04:00 PET / 04:00 COT).
- Todo `DateTime` é armazenado em **UTC** no Postgres. Sempre.
- A conversão para hora local acontece **só na camada de exibição do Unity**, usando o fuso do dispositivo.
- Nunca faça lógica de LiveOps com data local do cliente — é o vetor de cheat mais fácil que existe (mudar o relógio do celular).

---

## 3. ARQUITETURA DE INTERNACIONALIZAÇÃO (i18n)

Esta seção é nova na v2 e é **estrutural** — retrofitar i18n depois custa 3× mais do que fazer certo desde o início.

### 3.1 Locales oficiais

| Código | Idioma | Papel | Fallback |
|---|---|---|---|
| `pt-BR` | Português (Brasil) | **Idioma-fonte** (escrito primeiro) | — |
| `es-419` | Espanhol (América Latina) | Lançamento Fase B | `en-US` |
| `en-US` | Inglês (EUA) | Lançamento Fase C + idioma técnico | — |

> ⚠️ Use **`es-419`**, não `es-ES`. Espanhol da Espanha usa *vosotros*, vocabulário e tom diferentes — jogador argentino percebe na hora e reage mal. `es-419` é o código ISO para "Espanhol da América Latina".

**Cadeia de fallback:** `locale pedido` → `idioma base` → `en-US` → `chave crua`. Nunca renderize string vazia; renderize a chave (`ui.inventory.title`) para o bug ficar visível em QA.

### 3.2 🔑 A regra fundamental: o servidor manda CHAVE, nunca FRASE

Este é o erro que mata projetos multilíngues.

```typescript
// ❌ ERRADO — o servidor decide o idioma. Impossível de traduzir, impossível de testar.
socket.emit('combat', { message: 'Você derrotou o Guardião das Cinzas!' });

// ✅ CERTO — servidor manda semântica, cliente renderiza no idioma do jogador.
socket.emit('combat', {
  key: 'combat.enemy_defeated',
  params: { enemyId: 'mob_ashen_warden', xp: 450 }
});
```

O cliente resolve `mob_ashen_warden` para `"Guardião das Cinzas"` / `"Guardián de Cenizas"` / `"Ashen Warden"` conforme o locale ativo. Isso vale para **combate, chat de sistema, erros, e-mail no jogo, notificações push e recompensas**.

### 3.3 Pipeline de conteúdo localizado

Todo texto de conteúdo (nomes de item, descrição de skill, diálogo de quest) vive numa tabela **única e versionada**:

```
/content
  /source
    items.csv          ← designer edita AQUI (chave, pt-BR)
    skills.csv
    quests.csv
    monsters.csv
  /translated
    items.es-419.csv   ← tradutor devolve AQUI
    items.en-US.csv
  build-locales.ts     ← script: CSV → seed do Postgres + StringTables da Unity
```

O script `build-locales.ts` roda no CI e falha o build se:
- Uma chave existir em `pt-BR` mas faltar em `es-419` ou `en-US` (após o freeze de tradução).
- Uma string traduzida for **>140% do tamanho** da string em inglês (estoura a UI — ver 3.5).
- Um placeholder ICU (`{count}`, `{playerName}`) sumir ou mudar de nome na tradução.

### 3.4 Plural e gênero — a armadilha de PT/ES

Inglês é simples. Português e espanhol não são.

```
❌ "Você foi derrotado"        → e se a jogadora escolheu personagem feminino?
❌ "Você ganhou 1 itens"       → plural quebrado
❌ "Bem-vindo, {name}"         → "Bem-vinda" para personagem feminino
```

**Solução: ICU MessageFormat em todas as três línguas.**

```
combat.player_defeated =
  {gender, select,
    female {Você foi derrotada por {enemy}}
    other  {Você foi derrotado por {enemy}}}

loot.items_received =
  {count, plural,
    one   {Você recebeu # item}
    other {Você recebeu # itens}}
```

O `gender` do personagem é um campo no `Character` (`MALE | FEMALE | NEUTRAL`) e é enviado como parâmetro para toda string que precisa concordar. A Unity Localization suporta ICU nativamente via *Smart Strings*.

### 3.5 Expansão de texto e UI

Regra prática do setor: partindo do inglês, **português cresce ~25%** e **espanhol cresce ~30%**.

```
EN: "Equip"          (5 chars)
PT: "Equipar"        (7 chars)  +40%
ES: "Equipar"        (7 chars)  +40%

EN: "Attribute Points Remaining"   (26)
PT: "Pontos de Atributo Restantes" (28)
ES: "Puntos de Atributo Restantes" (28)
```

**Regras obrigatórias de UI:**
- Todo botão e label usa **layout flexível** (ContentSizeFitter / HorizontalLayoutGroup). Largura fixa é proibida em elementos com texto.
- Toda fonte tem **auto-size** com mínimo definido — nunca deixe o texto cortar.
- Faça o *layout pass* de QA com o locale mais longo (`es-419`), não com o inglês.
- Números, moedas e datas usam `CultureInfo` do locale: `1.234,56` (pt/es) vs `1,234.56` (en).

### 3.6 Fontes e caracteres

- Uma única fonte com suporte a **Latin Extended-A** cobre pt/es/en (acentos, ñ, ç, ã, õ).
- Gere o **atlas TMP com fallback dinâmico**, não estático — senão um `ẽ` inesperado vira quadrado.
- Nome de personagem: valide contra regex `^[\p{L}\p{N} ]{3,16}$` **no servidor**, permitindo acentos, mas rejeitando emoji, RTL override e caracteres invisíveis (vetor clássico de impersonation).

### 3.7 Moderação por idioma

Filtro de palavrão precisa de **três listas separadas** — palavrão em português não é palavrão em espanhol e vice-versa (e há falsos positivos cruzados famosos). Aplique no servidor, em: nome de personagem, nome de guilda, chat, e mensagens de correio.

### 3.8 Fora do jogo

Também precisa dos 3 idiomas: página da loja (Play/App Store), portal web, política de privacidade, termos de uso, e-mails transacionais, e **atendimento ao jogador**. Não adianta o jogo estar em espanhol se o suporte responde só em português.

---

## 4. DIREÇÃO DE ARTE 2.0 — "GRÁFICOS ATUALIZADOS" DE FORMA ATINGÍVEL

Você quer visual moderno. Isso é possível — mas o caminho **não** é "PBR fotorrealista + volumétrico", que é exatamente o que trava um Moto G e o que nenhum solo dev consegue produzir em volume.

### 4.1 A escolha: Stylized PBR

**Stylized PBR** = formas exageradas e silhuetas fortes, cores saturadas e intencionais, materiais com resposta PBR real (metal/rugosidade), mas **sem** perseguir fotorrealismo.

Por que essa é a escolha certa:

| Critério | Stylized PBR | PBR fotorrealista |
|---|---|---|
| Custo de produção por asset | 1× | 3–5× |
| Roda em tier LOW | ✅ | ❌ |
| Envelhece bem | ✅ (10+ anos) | ❌ (data em 3 anos) |
| Perdoa erro de artista amador | ✅ | ❌ implacável |
| Legibilidade em tela de 6" com 20 inimigos | ✅ | ❌ vira sopa visual |

Referências de direção (para briefing de artista, **não** para copiar): Diablo Immortal, Torchlight Infinite, Genshin Impact, Warcraft Rumble, Wayfinder.

**O que faz o jogo parecer "2025" e não "2015" — e é barato:**
1. **Iluminação, não polígonos.** Baked GI + Light Probes + uma direcional com sombra em cascata. É o que mais diferencia visualmente.
2. **Pós-processamento.** Bloom, color grading via LUT, vinheta sutil, ACES tonemapping. Custo quase zero, impacto enorme.
3. **VFX de habilidade com personalidade.** Um `Fireball` com trail, distorção, decal de chão e screen shake parece mais moderno que qualquer texture 4K.
4. **Feedback de impacto (game feel).** Hit stop de 60ms, flash branco no inimigo, números de dano com curva de animação, camera shake. **Isto é 80% da sensação de "jogo bom"** e é 100% código, zero arte.
5. **Silhueta.** Se o jogador reconhece a classe pela sombra, a arte está certa.

### 4.2 Budgets duros (não são sugestões — são portões de CI)

| Recurso | Tier LOW | Tier MID | Tier HIGH |
|---|---|---|---|
| Draw calls por frame | ≤ 120 | ≤ 220 | ≤ 400 |
| Triângulos na tela | ≤ 180k | ≤ 400k | ≤ 900k |
| Resolução de render | 0.7× nativa | 0.85× | 1.0× |
| Sombras | Só do jogador (blob ou 1 cascata) | 1 cascata 1024 | 2 cascatas 2048 |
| Skinned meshes simultâneos | ≤ 14 | ≤ 24 | ≤ 40 |
| Textura de personagem | 512² | 1024² | 1024² |
| Textura de ambiente | 512² atlas | 1024² atlas | 1024² atlas |
| Bones por rig | ≤ 48 | ≤ 64 | ≤ 72 |
| Partículas ativas | ≤ 300 | ≤ 800 | ≤ 2000 |
| Pico de RAM | ≤ 1.2 GB | ≤ 1.8 GB | ≤ 2.5 GB |
| Temperatura após 20 min | sem throttle térmico | | |

**Detecção de tier:** no primeiro boot, leia `SystemInfo.graphicsDeviceName`, `systemMemorySize` e `processorCount`, rode um benchmark de 3 segundos, e persista o tier escolhido. Sempre com override manual nas opções — o auto-detect erra e o jogador sabe o que quer.

### 4.3 URP — correções técnicas da v1.0

**❌ Erro da v1: "SRP Render Graph + GPU Instancing juntos".**
No URP, **SRP Batcher e GPU Instancing são mutuamente exclusivos por material** — o SRP Batcher tem prioridade e desliga silenciosamente o instancing. Decida por material:
- **Cenário estático (paredes, chão, props):** SRP Batcher ligado. É o caminho certo.
- **Hordas de monstros idênticos:** desligue `enableInstancing`-conflitantes e use **BatchRendererGroup** ou GPU Instancing explícito com material dedicado.
- Meça com o **Frame Debugger** no aparelho real. Nunca confie na contagem do editor.

**❌ Erro da v1: "VRS via Vulkan, economiza 20% de bateria".**
Variable Rate Shading em Android só existe em GPUs específicas (Adreno 660+, Mali recentes) — ou seja, **exatamente os aparelhos que não precisam da economia**. Marque como *nice-to-have* opcional no tier HIGH, nunca como diretriz de arquitetura. Os "20%" não têm fonte.

**✅ Acerto da v1: "Depth Priming desativado".**
Correto. GPUs móveis são *tile-based deferred* e já fazem hidden surface removal em hardware. Depth priming ali é trabalho duplicado. Mantenha **desativado**.

**Configuração canônica do URP Asset:**
```
Rendering Path            → Forward
Depth Priming             → Disabled
Opaque/Depth Texture      → Disabled (ligue só se um shader exigir)
HDR                       → Off no LOW, On no MID/HIGH
MSAA                      → Off no LOW, 2× no MID, 4× no HIGH
Shadow Cascades           → 1 (LOW) / 2 (MID/HIGH)
Shadow Distance           → 18m (LOW) / 30m (MID/HIGH)
Additional Lights         → Per Vertex (LOW) / Per Pixel máx 4 (MID+)
Light/Reflection Probes   → Baked. Zero realtime GI.
Render Scale              → 0.7 / 0.85 / 1.0
LOD Cross Fade            → Off (LOW)
```

**Vertex Animation Textures (VAT):** mantido da v1 — a ideia está certa. Use para bandeiras, vegetação, fluidos de habilidade e destroços. Anima na GPU, CPU fica livre.

### 4.4 Tamanho de download e Addressables

Este é um item **crítico** que faltava totalmente na v1.

- **Meta de download inicial: ≤ 150 MB.** Acima disso a conversão de instalação despenca — especialmente relevante em SA, onde dados móveis são caros.
- Use **Android App Bundle + Play Asset Delivery** e **On-Demand Resources** no iOS.
- Use **Addressables** para 100% do conteúdo de jogo (mapas, monstros, itens, VFX, áudio, StringTables por locale).
- Hospede o catálogo Addressables num **CDN** (Cloudflare R2 tem egress gratuito — importante para o orçamento).
- **StringTables são Addressables por locale:** o jogador brasileiro baixa só `pt-BR`. Não empacote os três idiomas no binário.

> Sem Addressables, cada evento de LiveOps exige uma nova submissão na loja e 1–3 dias de review. Com Addressables, você publica conteúdo novo em minutos. É a diferença entre um jogo *live* e um jogo *estático*.

### 4.5 De onde vem a arte (seja honesto agora)

Você não vai modelar, riggar e animar 4 classes, 60 monstros, 8 bosses e 200 itens sozinho. Escolha o caminho na Etapa 1, não na Etapa 6:

| Caminho | Custo | Prazo | Risco |
|---|---|---|---|
| **Pacotes coerentes** (Synty POLYGON, KayKit, Quaternius) | US$ 200–800 total | imediato | Visual "asset-flip" se não customizar |
| **Asset Store + retarget de animação** (Mixamo) | US$ 300–1.500 | 1–2 semanas | Inconsistência de estilo entre pacotes |
| **Artista freelancer 3D** (BR/LatAm) | R$ 800–2.500 por personagem completo | 2–4 semanas cada | Melhor resultado, maior custo |
| **IA generativa para concept + artista para produção** | híbrido | — | Concept sim; asset final de jogo ainda não |

**Recomendação:** comece com **um único pacote coerente** (todo o jogo no mesmo estilo) e invista dinheiro só nas 4 classes jogáveis e nos bosses. Ninguém repara no monstro genérico; todo mundo repara no próprio personagem.

---

## 5. ARQUITETURA DE REDE — A SEÇÃO QUE FALTAVA

**Este é o risco número 1 do projeto inteiro.** Se essa camada estiver errada, nada mais importa.

### 5.1 Decisão: Colyseus 0.16.5, não Socket.io cru

> ⚠️ **Trave em 0.16.5.** O servidor Colyseus já está em 0.17, mas o SDK cliente parou em 0.16.22 e o par 0.17↔0.16 **quebra no handshake** (`consumeSeatReservation`). Testado e confirmado. Ver a Parte A, armadilha nº 1.

| Critério | Socket.io cru (v1.0) | **Colyseus (v2.0)** |
|---|---|---|
| Cliente Unity C# oficial | ❌ não existe | ✅ SDK oficial mantido |
| Salas autoritativas | você escreve | ✅ nativo |
| Sincronização de estado delta binária | você escreve | ✅ nativo (Schema) |
| Matchmaking | você escreve | ✅ nativo |
| Múltiplos processos / máquinas | ❌ não resolvido na v1 | ✅ driver Redis + presence |
| Licença | MIT | MIT |
| Linguagem | TypeScript | TypeScript (mesmo stack) |

**Topologia:**
```
                    ┌──── NestJS (Fastify) ── REST ── Prisma ── Postgres
[ Unity C# ] ───────┤     login, inventário, loja, guilda, mercado, perfil
                    │
                    └──── Colyseus ───── Redis (presence + state)
                          salas de dungeon, arena, vila
                          simulação autoritativa @ 20 Hz
```

NestJS e Colyseus são **dois processos separados** que compartilham Postgres e Redis. O NestJS emite o JWT; o Colyseus valida esse mesmo JWT no `onAuth` da sala. Não duplique lógica de autenticação.

### 5.2 Tick, predição e reconciliação (obrigatório)

```
CLIENTE (60 fps)                        SERVIDOR (20 Hz = 50 ms)
─────────────────────────────────────────────────────────────────
1. Jogador toca o joystick
2. Aplica movimento LOCALMENTE já      ← predição: resposta instantânea
3. Guarda {seq: 142, input, t} no buffer
4. Envia input ao servidor  ───────────► 5. Valida: distância ≤ maxSpeed × dt?
                                        6. Aplica no estado autoritativo
                            ◄─────────── 7. Devolve {seq: 142, posição real}
8. Compara: predição == autoritativo?
   ├─ sim  → segue a vida (99% dos casos)
   └─ não  → snap para o autoritativo e
             re-simula inputs 143..N     ← reconciliação
```

**Parâmetros canônicos:**

| Parâmetro | Valor | Motivo |
|---|---|---|
| Tick do servidor | **20 Hz** (50 ms) | Suficiente para ARPG; 30 Hz custa 50% mais CPU |
| Envio de input do cliente | 20 Hz | Casado com o tick |
| Broadcast de estado | 10–20 Hz (adaptativo) | Cai para 10 Hz sob RTT alto |
| Buffer de interpolação | 100 ms | Suaviza outros jogadores |
| Tolerância de reconciliação | 0.15 m | Abaixo disso, ignora — evita jitter |
| Timeout de sala | 30 s sem input | Desconecta e persiste |

**Interpolação de entidades:** os *outros* jogadores e monstros são renderizados **100 ms no passado**, interpolando entre os dois últimos snapshots. Nunca extrapole posição de outro jogador — gera teleporte visual.

**Lag compensation:** para o Ranger (projéteis), o servidor rebobina a posição dos alvos em `RTT/2` ao validar o acerto. Limite a compensação a **200 ms** — acima disso o jogador com lag alto começa a acertar coisas injustas ("morri atrás da parede").

### 5.3 Orquestração de salas e capacidade

**BullMQ não é matchmaker.** Ele é fila de jobs (e-mail, recompensa offline, relatório) — mantenha para isso.

```
Colyseus Room Types
├─ VillageRoom     40 jogadores  · tick 10 Hz · social, sem combate
├─ DungeonRoom      4 jogadores  · tick 20 Hz · simulação completa
├─ SpireRoom        1 jogador    · tick 20 Hz · torre infinita
└─ ArenaRoom       10 jogadores  · tick 20 Hz · PvP (fase 2)
```

**Capacidade estimada:** um processo Node com 2 vCPU sustenta ~40–60 `DungeonRoom` simultâneas (≈ 160–240 jogadores em combate). Para 1.000 CCU: **4–6 processos** + o driver Redis do Colyseus para presence e roteamento. Escale por processo (`cluster`/PM2 ou pods), nunca com uma única instância gigante — Node é single-threaded por processo.

### 5.4 Persistência e recuperação de falha

O estado quente vive em RAM/Redis; o Postgres é a verdade fria.

| Evento | Ação |
|---|---|
| Cada 30 s durante a run | Snapshot da run no Redis (TTL 1 h) |
| Fim da dungeon | **Transação única:** loot + XP + ledger + progresso, tudo ou nada |
| Jogador desconecta | 90 s de graça para reconectar na mesma sala |
| Processo crasha | Ao reiniciar, lê snapshots do Redis, credita recompensas parciais via job |

**Nunca** credite recompensa em duas transações separadas. `ItemInstance` criado + `EconomyLedger` inserido + `QuestProgress` atualizado = **um `prisma.$transaction`**. É isso que impede duplicação.

### 5.5 Anti-cheat (o Ledger não cobre tudo)

| Vetor | Defesa (100% servidor) |
|---|---|
| Speedhack | `distância ≤ maxSpeed × dt × 1.15` por tick; 3 falhas = kick |
| Teleport | Distância máxima por tick + raycast de parede |
| Dano inflado | Servidor calcula dano; cliente só pede "usei skill X no alvo Y" |
| Cooldown burlado | Timestamp do último uso no servidor; a UI é só espelho |
| Replay de pacote | `seq` monotônico por conexão; rejeita repetido ou fora de ordem |
| Flood de comandos | Rate limit por opcode (ex.: ataque ≤ 5/s) |
| Farm por bot | Telemetria: sessões >6 h, variância de rota, cliques perfeitos → fila de revisão manual |
| Relógio do celular | Toda lógica temporal usa `now()` do servidor. Sempre. |
| Item duplicado | `EconomyLedger` + `ItemInstance` com dono único e transação atômica |

### 5.6 Versionamento de protocolo e force update

```json
GET /api/v1/bootstrap
{
  "minClientVersion": "1.4.0",
  "latestClientVersion": "1.5.2",
  "protocolVersion": 7,
  "addressablesCatalogUrl": "https://cdn.../catalog_v152.json",
  "maintenance": { "active": false, "messageKey": null, "etaUtc": null },
  "locales": ["pt-BR", "es-419", "en-US"]
}
```

Toda sessão começa por aqui, **antes do login**. Se `clientVersion < minClientVersion`, tela bloqueante com botão para a loja. Cliente com `protocolVersion` diferente é recusado no handshake do Colyseus. Sem isso, uma atualização de servidor derruba todos os jogadores em versão antiga sem explicação.

---

## 6. BACKEND NESTJS — CORREÇÕES CRÍTICAS

### 6.1 Setup correto do Prisma 7 (a v1 não bootava)

O Prisma 7 removeu o motor Rust, virou ESM puro e exige driver adapter. A configuração da v1.0 falha no primeiro `npm run start`.

> ✅ **O `schema.prisma` que acompanha este blueprint foi validado contra o Prisma CLI 7.9.1** (`prisma validate` → *valid*). 32 modelos, 20 enums.

**⚠️ Pegadinha nº 1 do Prisma 7.9+:** o campo `url` **não é mais aceito no bloco `datasource`**. Se você escrever a sintaxe antiga, o `prisma validate` falha com `P1012` antes mesmo de rodar o servidor:

```prisma
// ❌ NÃO FUNCIONA MAIS
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")   // ← erro P1012
}

// ✅ CORRETO — a connection string vive só no prisma.config.ts
datasource db {
  provider = "postgresql"
}
```

**`package.json`**
```json
{ "type": "module" }
```

**`tsconfig.json`**
```json
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "bundler",
    "target": "ES2023",
    "strict": true,
    "esModuleInterop": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true
  }
}
```

**`prisma.config.ts`** (na raiz — o `.env` NÃO é mais carregado automaticamente)
```typescript
import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations", seed: "tsx prisma/seed.ts" },
  datasource: { url: env("DATABASE_URL") },
});
```

**Instanciação do cliente**
```typescript
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client.js";  // .js obrigatório em ESM

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
export const prisma = new PrismaClient({ adapter });
```

**Instalação**
```bash
npm i @prisma/client @prisma/adapter-pg pg
npm i -D prisma tsx
npx prisma migrate dev --name init     # ⚠️ migrate, NUNCA db push
```

### 6.2 RLS: a verdade desconfortável

A v1.0 afirmava que RLS blindaria os dados. **Não blinda.** O Prisma conecta com uma connection string única de service role, que **bypassa RLS por design**. Do jeito que estava escrito, o RLS era decoração.

**Decisão v2.0:** a segurança vive na **camada de aplicação** (guards do NestJS + escopo obrigatório por `characterId` em toda query), com **auditoria** por cima. RLS fica reservado para as tabelas realmente sensíveis, se e quando você adotar o padrão de role restrito + `SET LOCAL app.current_user_id` por transação.

**Regra prática que substitui o RLS:** **nenhuma** query de personagem pode ser escrita sem `where: { characterId }` derivado do JWT — nunca de um parâmetro que o cliente mandou. Isso é IDOR, o bug mais comum em backend de jogo.

```typescript
// ❌ IDOR — o cliente manda o characterId que quiser
@Get('inventory/:characterId')
async get(@Param('characterId') id: string) { ... }

// ✅ o characterId vem da sessão, validado contra o userId do token
@Get('inventory')
async get(@CurrentCharacter() char: CharacterContext) { ... }
```

### 6.3 BigInt quebra JSON — resolva antes de bater no bug

`JSON.stringify(1n)` lança `TypeError`. Você vai bater nisso na primeira rota de inventário.

```typescript
// main.ts — antes do bootstrap
(BigInt.prototype as any).toJSON = function () { return this.toString(); };
```

Consequência: valores monetários chegam ao cliente como **string**. O C# faz `long.Parse()`. Documente isso no contrato de API — é fonte garantida de bug se ficar implícito.

### 6.4 Ledger vs saldo materializado

A v1 tinha `Character.gold` **e** `EconomyLedger`. Duas fontes de verdade divergem na primeira falha parcial.

**Modelo canônico v2:**
- `EconomyLedger` = **verdade imutável**. Append-only. Nunca `UPDATE`, nunca `DELETE`.
- `WalletBalance` = **cache materializado**, atualizado na **mesma transação** do ledger.
- Job noturno de reconciliação: `SUM(ledger) == WalletBalance`? Divergência = alerta imediato no Sentry + investigação. Divergência silenciosa em economia de jogo é sempre exploit.

```typescript
await prisma.$transaction(async (tx) => {
  await tx.economyLedger.create({
    data: { characterId, currency: 'GOLD', amount: 500n,
            operation: 'DUNGEON_REWARD', referenceId: runId },
  });
  await tx.walletBalance.update({
    where: { characterId_currency: { characterId, currency: 'GOLD' } },
    data: { amount: { increment: 500n } },
  });
});
```

### 6.5 Webhook de pagamento — correção do `proxy.ts`

**A v1 estava errada em dois pontos:** (a) `proxy.ts` não existe no Next.js — o arquivo é `middleware.ts`; (b) middleware roda em edge runtime e **não é lugar de validar HMAC**, porque o acesso ao raw body é problemático e qualquer parse quebra a assinatura.

**Correto — Route Handler:**
```
/web-portal/app/api/webhooks/[provider]/route.ts
```

```typescript
export async function POST(req: Request, { params }) {
  const raw = await req.text();                    // RAW, antes de qualquer parse
  const sig = req.headers.get('x-signature');

  if (!verifyHmac(raw, sig, process.env.WEBHOOK_SECRET))
    return new Response('invalid signature', { status: 401 });

  const event = JSON.parse(raw);

  // IDEMPOTÊNCIA — gateways reenviam. Sem isso o jogador recebe 3× o pacote.
  const existing = await prisma.paymentOrder.findUnique({
    where: { providerEventId: event.id },
  });
  if (existing?.status === 'CREDITED') return new Response('ok', { status: 200 });

  await creditPurchase(event);                     // transação atômica
  return new Response('ok', { status: 200 });
}
```

**Três regras não negociáveis de webhook:**
1. Valide a assinatura no **raw body**, antes de qualquer parse.
2. **Idempotência por `providerEventId`** — gateways reenviam por design.
3. Responda `200` rápido; faça o trabalho pesado numa fila BullMQ. Timeout no webhook = reenvio infinito.

### 6.6 Observabilidade (ausente na v1)

Sem isso você não opera um jogo live — você adivinha.

| Camada | Ferramenta | Custo inicial |
|---|---|---|
| Erros (server + Unity) | Sentry | grátis até 5k eventos/mês |
| Logs estruturados | Pino → stdout | R$ 0 |
| Métricas de sala | Prometheus + Grafana Cloud | grátis até 10k séries |
| Analytics de produto | PostHog self-hosted ou GameAnalytics | R$ 0 |
| Uptime | UptimeRobot | R$ 0 |

**Métricas que importam desde o dia 1:** CCU, salas ativas por tipo, tick time p95, RTT p95 **por país**, taxa de reconciliação, D1/D7 retention, funil de tutorial, conversão de compra.

> O RTT p95 **segmentado por país** é a sua métrica mais importante. É ela que diz se a Colômbia é um mercado ou um problema de suporte.

---

## 7. SCHEMA CANÔNICO

O schema completo está no arquivo **`schema.prisma`** que acompanha este blueprint. Resumo do que mudou:

**Modelos novos (ausentes na v1):**
`RefreshToken` · `ItemDefinition` · `ItemInstance` · `EquipmentSlot` · `SkillDefinition` · `CharacterSkill` · `MonsterDefinition` · `LootTable` · `LootEntry` · `DungeonDefinition` · `DungeonRun` · `QuestDefinition` · `QuestProgress` · `Guild` · `GuildMember` · `Friendship` · `MailMessage` · `MarketListing` · `WalletBalance` · `PaymentOrder` · `LocalizedString` · `Companion` · `Familiar` · `AuditLog` · `Sanction`

**Mudanças estruturais:**
- `String` de domínio → **`enum`** (`CharacterClass`, `CurrencyType`, `ItemRarity`…). Type-safety em vez de string mágica.
- `ItemDefinition` (o que o item é) separado de `ItemInstance` (o que **aquele** item rolou). Sem isso não existe loot de ARPG.
- Índices explícitos em todo campo de busca quente.
- `LocalizedString` para nome/descrição de todo conteúdo, com chave + locale.
- `gender` no `Character` — necessário para concordância em pt/es (Seção 3.4).
- `shardId` e `region` no `Character` — preparado para o shard NA da Fase C.

---

## 8. ESCOPO DE LANÇAMENTO (o corte que salva o cronograma)

A v1.0 colocava PvP massivo, World Boss e faction war no lançamento. Isso é o que transforma um projeto de 18 meses em um de 4 anos.

### v1.0 — Soft launch Brasil (o mínimo que é um jogo bom)
```
✅ 4 classes · nível máximo 40
✅ Campanha: 3 zonas, ~25 quests de história
✅ 8 dungeons co-op (4 jogadores) · 3 dificuldades
✅ 4 bosses
✅ Loot com afixos aleatórios + upgrade de equipamento
✅ Guildas (chat, ranking, bônus passivo)
✅ Chat global / guilda / grupo · correio
✅ Loja premium + battle pass · Pix
✅ 3 idiomas
✅ Eventos diários (LiveOps)
```

### v1.1 → v1.3 (pós-lançamento, cada 6–10 semanas)
```
The Spire (torre infinita) · Vanity · Companions · Familiars
Mercado entre jogadores · Expeditions · Codex · nível 50
```

### v2.0 (só depois de retenção D7 comprovada)
```
Faction War (Ironvow vs Ashenfold) · Arena PvP · World Boss · nível 60
```

> **Por que essa ordem:** PvP é caríssimo (balanceamento, anti-cheat, matchmaking por MMR) e **só retém quem já ficou**. Ele não traz jogador novo. Co-op de qualidade traz. Lance o co-op, prove que o D7 é bom, e só então gaste no PvP.

---

## 9. MONETIZAÇÃO E CONFORMIDADE (SA)

### 9.1 A realidade das taxas de loja — a v1 estava desatualizada

A premissa "vender no portal web e escapar dos 30%" **não é mais verdade e não é segura do jeito descrito**.

**Android — Brasil, hoje (ago/2026):** o Google reestruturou taxas e passou a permitir pagamento externo, mas o rollout começou por EUA/Reino Unido/EEE em 30/jun/2026, chega a Austrália/Japão/Coreia até o fim de 2026, e ao **resto do mundo — incluindo Brasil — só até setembro de 2027**. Ou seja: **linkar para sua loja web de dentro do app ainda viola a política do Google Play no Brasil** e é risco real de remoção.

**iOS — Brasil:** mudou de verdade. Desde 18/jun/2026, por acordo com o CADE, a Apple permite lojas alternativas e pagamento de terceiros no Brasil. Mas não é grátis: compras totalmente fora do ambiente Apple pagam **alíquota mínima de 5%**; com botão/link dentro do app direcionando para site próprio, **15%**; sem qualquer link clicável, **0%**.

**Estratégia v2.0 (conforme e realista):**
```
DENTRO DO APP     → IAP nativo Google/Apple. É a receita principal. Aceite a taxa.
FORA DO APP       → portal web, divulgado por Discord, redes sociais, e-mail, creators.
                    Ofereça 15–20% de bônus de gema como incentivo orgânico.
                    ZERO link ou menção de preço externo dentro do jogo (Android).
REVISAR           → setembro/2027, quando as regras do Google chegarem ao Brasil.
```

### 9.2 Pagamentos na América do Sul

| País | Meio dominante | Gateway recomendado |
|---|---|---|
| 🇧🇷 Brasil | **Pix** (>60% do e-commerce digital) + cartão + boleto | Asaas, Pagar.me, Mercado Pago |
| 🇦🇷 Argentina | Mercado Pago, cartão em quotas | Mercado Pago, dLocal |
| 🇨🇱 Chile | Webpay, cartão | Mercado Pago, dLocal |
| 🇨🇴 Colômbia | PSE, Nequi | dLocal, Mercado Pago |
| 🇵🇪 Peru | Yape, cartão | dLocal |
| 🇺🇸 EUA (Fase C) | cartão | Stripe |

**Pix é a sua vantagem competitiva no Brasil:** confirmação em segundos, taxa ~1% (vs 4–5% de cartão), sem chargeback. Um jogador sem cartão de crédito — enorme parcela do público — consegue comprar. **Priorize Pix acima de tudo.**

⚠️ **Preço regional obrigatório.** Um pacote de US$ 4,99 é razoável nos EUA e proibitivo no Peru. Defina tiers por país em moeda local, com números "redondos" culturalmente (R$ 9,90 / R$ 19,90 / R$ 49,90). Argentina exige revisão frequente por inflação.

### 9.3 Conformidade legal

**Brasil**
- **CNPJ** — praticamente todo gateway sério exige. MEI não cobre (jogos não está no rol); vá de **ME/Simples Nacional**.
- **LGPD** — política de privacidade nos 3 idiomas, base legal para cada dado coletado, canal de exclusão de conta e dados funcionando de verdade, encarregado (DPO) nomeado.
- **Classificação indicativa** — obrigatória. Jogos exclusivamente digitais podem ser **autoclassificados** desde que sigam os critérios brasileiros e exibam corretamente símbolos e descritores — na prática, via questionário **IARC** no Play Console / App Store Connect. A Portaria MJSP nº 1.048/2025 renovou as regras e criou obrigações inéditas para aplicativos digitais.
- **ECA + loot box** — se houver caixa aleatória: publique as **taxas de drop**, limite gasto de menores, e implemente *pity system*. É pressão regulatória crescente e boa prática de retenção.
- **CDC** — direito de arrependimento em 7 dias para compra digital.

**Demais países de lançamento**
| País | Norma de dados | Observação |
|---|---|---|
| 🇦🇷 Argentina | Ley 25.326 | Registro na AAIP se tratar dados em escala |
| 🇨🇱 Chile | Ley 21.719 (nova, alinhada ao GDPR) | Mais rígida que a LGPD |
| 🇨🇴 Colômbia | Ley 1581 | Registro de base de dados na SIC |
| 🇵🇪 Peru | Ley 29733 | |

> Redigir os documentos legais **uma vez, nos 3 idiomas**, com um advogado, custa entre R$ 2.000 e R$ 5.000 e resolve todos os países de uma vez. Faça isso antes do soft launch, não depois da primeira notificação.

---

## 10. CUSTOS REAIS

### Fase 1 — Desenvolvimento local (meses 1–8)
| Item | Custo |
|---|---|
| Unity Personal (livre até US$ 200k de receita/funding em 12 meses) | R$ 0 |
| Docker local (Postgres + Redis) | R$ 0 |
| Supabase / Vercel free tier | R$ 0 |
| Cursor Pro | ~R$ 110/mês |
| **Pacote de assets 3D inicial** | **R$ 400–3.000 (uma vez)** |
| **Total** | **~R$ 110/mês + assets** |

### Fase 2 — Alfa fechado (100–300 testadores)
| Item | Custo/mês |
|---|---|
| VPS São Paulo (NestJS + Colyseus, 4 vCPU) — Hetzner/Fly.io GRU/Magalu | R$ 120–220 |
| Postgres gerenciado (Supabase Pro / Neon) | R$ 130 |
| Redis (Upstash) | R$ 0–60 |
| CDN Addressables (Cloudflare R2 — egress grátis) | R$ 0–30 |
| Sentry / Grafana / PostHog (free tiers) | R$ 0 |
| Google Play (US$ 25, uma vez) + Apple Developer (US$ 99/ano) | ~R$ 55/mês amortizado |
| **Total** | **~R$ 300–500/mês** |

### Fase 3 — Comercial (1.000 CCU)
| Item | Custo/mês |
|---|---|
| 4–6 instâncias de app (Colyseus + NestJS) | R$ 900–1.500 |
| Postgres alta disponibilidade + réplica de leitura | R$ 600–900 |
| Redis clusterizado | R$ 250–400 |
| CDN + storage | R$ 150–300 |
| Observabilidade paga | R$ 200–400 |
| Contador (Simples Nacional) | R$ 350–600 |
| **Infraestrutura** | **~R$ 2.500–4.100/mês** |

> ⚠️ **A v1 estimava R$ 1.000/mês para 1.000 CCU — otimista em 2,5×.** Simulação autoritativa em tempo real é cara em CPU.
>
> **Mas o custo real do projeto não é infra.** É **arte** (R$ 15.000–60.000 para um pacote decente de ARPG) e **aquisição de usuário** (CPI de R$ 3–12 na América do Sul). A infraestrutura é o item mais barato da planilha.

---

## 11. ROTEIRO DE IMPLEMENTAÇÃO

> A ordem mudou em relação à v1.0. A Etapa 0 é nova e é um **portão de risco** — não a pule.

### 🚦 ETAPA 0 — PROVA DE CONCEITO DE REDE *(1 semana — PORTÃO)*
**Por que primeiro:** se 4 celulares em 4G não conseguem se mover e bater num monstro de forma fluida, toda a arquitetura muda. Descobrir isso na semana 1 custa 1 semana. Descobrir no mês 8 custa o projeto.

1. Servidor Colyseus mínimo em VPS São Paulo. Tick 20 Hz. Uma `DungeonRoom` de 4 slots.
2. Cliente Unity: um cubo, joystick virtual, um monstro que anda e bate.
3. Implemente **predição + reconciliação + interpolação** desde já. Não é opcional.
4. Overlay de debug na tela: RTT, tick time, taxa de reconciliação, pacotes/s.
5. Teste com **4 celulares reais em 4G** (não Wi-Fi), incluindo um aparelho tier LOW.
6. Se possível, teste com alguém em Buenos Aires ou Bogotá.

**Critério de aprovação:** RTT p95 < 120 ms em 4G brasileiro, reconciliação < 5% dos ticks, e o movimento *parece* instantâneo. ❌ Reprovou → revisar tick, taxa de broadcast ou tamanho do payload **antes** de seguir.

### 🏁 ETAPA 1 — FUNDAÇÃO *(1 semana)*
Monorepo `/game-client` `/game-server` `/realtime-server` `/web-portal` `/content`. Docker Compose (Postgres 16 + Redis 7). Prisma 7 com a config correta da Seção 6.1. `prisma migrate dev`. Git + CI mínimo. Decisão de arte tomada (Seção 4.5).

### 📚 ETAPA 2 — DADOS DE CONTEÚDO E i18n *(2 semanas)*
**Antes dos sistemas, os dados.** CSVs em `/content/source` (items, skills, monsters, quests). Script `build-locales.ts` → seed Postgres + StringTables Unity. Unity Localization configurada com os 3 locales e ICU. Um item, uma skill e um monstro renderizando nome traduzido nos 3 idiomas. **Nenhuma string hardcoded a partir daqui.**

### 🔐 ETAPA 3 — IAM *(1 semana)*
Registro/login REST. **Argon2id** (não bcrypt). JWT curto (15 min) + refresh rotativo com detecção de reúso. Guest account com upgrade posterior. Rate limit por IP. Endpoint `/bootstrap` (Seção 5.6). Criação de personagem com validação de nome (Seção 3.6).

### ⚔️ ETAPA 4 — COMBATE AUTORITATIVO *(4–6 semanas — o coração)*
Skills server-side com cooldown, custo de recurso e alcance. Fórmula de dano no servidor (a v1 já estava certa aqui). Máquina de estados de monstro (aggro, patrulha, telegrafia, ataque). Boss com 3 fases. Hit stop, screen shake, números de dano. `DistributePointsCommand` validado.

**Aqui é onde o jogo passa a ser divertido ou não.** Reserve tempo para iterar no *feel*. Se não estiver gostoso com um cubo e um monstro, não vai ficar gostoso com arte bonita.

### 🎒 ETAPA 5 — INVENTÁRIO, LOOT E ECONOMIA *(3 semanas)*
`ItemDefinition` + `ItemInstance` com rolagem de afixos. Slots de equipamento com validação por classe. Loot tables com pesos. `EconomyLedger` + `WalletBalance` em transação única (Seção 6.4). Job noturno de reconciliação. Upgrade de equipamento.

### 🏰 ETAPA 6 — DUNGEONS E PROGRESSÃO *(4 semanas)*
Geração de layout de dungeon com seed (mesmo seed = mesmo mapa para os 4 jogadores). Matchmaking Colyseus. Sistema de grupo. 8 dungeons × 3 dificuldades. Campanha e quests. Curva de XP até 40.

### 👥 ETAPA 7 — SOCIAL *(3 semanas)*
Guildas. Chat (global/guilda/grupo) com filtro de palavrão por idioma. Correio. Lista de amigos e bloqueio. Rankings.

### 💰 ETAPA 8 — MONETIZAÇÃO E LIVEOPS *(3 semanas)*
Loja premium + IAP nativo Google/Apple. Portal Next.js com **Pix** (Asaas ou Mercado Pago). Webhook com HMAC + idempotência (Seção 6.5). Battle pass. `EventDefinition` remoto. Painel de GM (banir, compensar, inspecionar personagem).

### 🚀 ETAPA 9 — POLIMENTO E SOFT LAUNCH *(6–10 semanas)*
Otimização no tier LOW até bater os budgets da Seção 4.2. Load test (k6 no WebSocket, 500 conexões simuladas). Passe de QA de localização nos 3 idiomas. Classificação IARC. Documentos legais. Fichas de loja em 3 idiomas. **Soft launch em uma região só** (sugestão: Sul do Brasil) para medir D1/D7 antes de gastar em marketing.

---

## 12. CRONOGRAMA REALISTA

Escopo v1.0 da Seção 8 (co-op, sem PvP), com Cursor ajudando e **assets comprados**:

| Marco | Solo full-time | Solo meio período | Equipe de 3–4 |
|---|---|---|---|
| Etapa 0 aprovada | 1 semana | 2–3 semanas | 1 semana |
| **Vertical slice** (1 classe, 1 dungeon, 1 boss, 4p, 3 idiomas) | 3–5 meses | 8–12 meses | 2–3 meses |
| **Alfa fechado** (4 classes, 8 dungeons, guilda, economia) | +7–10 meses | +16–22 meses | +5–7 meses |
| **Soft launch BR** | +4–7 meses | +9–14 meses | +3–5 meses |
| **TOTAL até a loja** | **15–24 meses** | **33–48 meses** | **10–15 meses** |
| Fase B (espanhol, +4 países) | +1–2 meses | +3 meses | +1 mês |

**O que ACELERA (faça):**
- Cortar o Warden e lançar com 3 classes — economiza ~1,5 mês.
- Um único pacote de assets coerente em vez de artista sob medida — economiza 3–5 meses.
- Dungeons com layout gerado por seed em vez de 8 mapas feitos à mão — economiza ~2 meses.
- Etapa 0 no lugar certo — economiza os 6 meses que você perderia refazendo a arquitetura.

**O que ATRASA (evite):**
- PvP no lançamento: **+8 a 14 meses**.
- Fazer a própria arte: **+12 a 24 meses**.
- Retrofitar i18n depois: +2 meses e bugs em todo lugar.
- Testar performance só no fim: +3 meses de refatoração de renderização.
- Mundo único em vez de shardado: +2 meses de complexidade sem benefício.

---

## 13. DEFINITION OF DONE

Uma etapa só está concluída quando **todos** os itens são verdade:

- [ ] Roda num **aparelho tier LOW real**, não só no editor.
- [ ] Funciona nos **3 idiomas** sem string hardcoded e sem texto cortado.
- [ ] Toda validação relevante acontece **no servidor**.
- [ ] Toda transação de economia passa pelo **Ledger**, em transação atômica.
- [ ] Existe **migration** versionada (nunca `db push`).
- [ ] Erros aparecem no **Sentry**, não só no console.
- [ ] Um jogador desconectando no pior momento possível **não corrompe** o estado.
- [ ] Nenhum nome, asset ou texto derivado de *Clash for Dawn*.

---

## 14. OS TRÊS RISCOS QUE MATAM O PROJETO

**1. Netcode ruim.** Mitigação: Etapa 0 antes de tudo. *Sintoma de alerta:* você adiou os testes com celular real.

**2. Arte inexistente ou inconsistente.** Mitigação: decidir o caminho na Etapa 1, um pacote coerente, dinheiro só nas 4 classes. *Sintoma:* seis meses de projeto e ainda usando cápsulas brancas.

**3. Escopo crescendo.** Mitigação: a lista da Seção 8 é um **contrato**. Toda feature nova vai para v1.1, não para o lançamento. *Sintoma:* "seria legal se também tivesse...".

---

> **Última palavra de engenharia:** este blueprint descreve um jogo que dá para fazer. O da v1.0 descrevia um jogo que precisaria de um estúdio de 20 pessoas. A diferença não está na ambição — está em **onde a ambição foi gasta**. Gaste no *game feel* do combate e na fluidez da rede. Economize em quantidade de sistemas, classes e conteúdo de lançamento. Sistemas você adiciona depois; primeira impressão você tem uma só.


---

# PARTE C — SISTEMAS DE JOGO

> **O que é este arquivo:** cada sistema do ARPG de referência, reconstruído do zero, renomeado, e **melhorado** com o que se aprendeu em 10 anos de design de jogos mobile.
>
> **Regra de ouro:** copiamos **como o sistema funciona**. Nunca arquivo, texto, arte, som ou código.
> Mecânica não tem proteção autoral. Expressão tem.

---

## 🚦 O QUE COPIAR E O QUE NÃO

| ✅ Copie à vontade | ❌ Nunca |
|---|---|
| Toda a lógica de sistema deste documento | Extrair/descompilar o APK original |
| Estrutura de progressão, fórmulas, loops | Modelos, texturas, áudio, ícones, fontes |
| Layout de UI (convenção do gênero) | Textos de quest, diálogo, descrição |
| Ritmo de eventos diários | Nomes: Luxis, Angeli, Brotherhood, Order, Dark Lord, Chosen One |
| Sensação do combate | Trilha sonora |
| Economia e monetização | Marketing como "remake" ou "2.0" |

> ⚠️ Jogo encerrado **não** significa domínio público. Copyright dura décadas, e a LEDO lançou um sucessor na Coreia. A marca está viva. Mas nada disso te impede — porque nada na coluna esquerda é protegido.

---

## 📋 ÍNDICE DE SISTEMAS

| # | Sistema original | Nome neste projeto | Fase | Complexidade |
|---|---|---|---|---|
| 1 | Classes (8) | **Classes** (4 → 8) | v1.0 | ●●●○○ |
| 2 | Combate hack'n'slash | **Combate** | v1.0 | ●●●●● |
| 3 | Campanha + zonas | **Campanha** | v1.0 | ●●●○○ |
| 4 | Co-op Dungeons | **Dungeons** | v1.0 | ●●●●○ |
| 5 | Equipamento + enhance | **Forja** | v1.0 | ●●●○○ |
| 6 | Guildas | **Guildas** | v1.0 | ●●○○○ |
| 7 | Chat + comunidade | **Social** | v1.0 | ●●○○○ |
| 8 | Eventos diários | **LiveOps** | v1.0 | ●●●○○ |
| 9 | Loja + gemas | **Loja** | v1.0 | ●●○○○ |
| 10 | Illusionary Palaces | **The Spire** | v1.1 | ●●○○○ |
| 11 | Costumes | **Vanity** | v1.1 | ●○○○○ |
| 12 | Mercenários + Pactos | **Companions** | v1.2 | ●●●●○ |
| 13 | Treasure Hunting | **Expeditions** | v1.2 | ●●○○○ |
| 14 | Collection Gallery | **Codex** | v1.2 | ●○○○○ |
| 15 | Dragões / pets | **Familiars** | v1.3 | ●●●○○ |
| 16 | Montarias | **Mounts** | v1.3 | ●●○○○ |
| 17 | Arena PvP | **Arena** | v2.0 | ●●●●○ |
| 18 | Co-op Boss Battles | **World Bosses** | v2.0 | ●●●●○ |
| 19 | Faction vs Faction | **Faction War** | v2.0 | ●●●●● |
| 20 | Mercado / troca | **Market** | v2.0 | ●●●○○ |

---

## 1. CLASSES

**Original:** 8 classes com skills customizáveis (confirmadas: Warrior, Mage, Archer, Priest).

**Aqui:** 8 heróis, **herói = classe**, 4 no lançamento. Especificação completa na **Parte E2**.

| Classe | Papel | Atributo | Recurso | Identidade |
|---|---|---|---|---|
| **Vanguard** | Tank | Vitality | Rage (ganha apanhando) | Puxa hordas, stun, escudo de grupo |
| **Arcanist** | DPS área | Intelligence | Aether (regenera) | Dano catastrófico, morre em 2 hits |
| **Ranger** | DPS alvo único | Agility | Focus (ganha acertando) | Crítico massivo, mobilidade |
| **Warden** | Suporte | Int + Vit | Aether | Cura, escudo, purificação |

Roadmap: `Reaver` · `Shadowblade` · `Templar` · `Beastcaller`

### 🔼 Melhorias sobre o original
1. **Recurso por classe, não mana genérica.** Rage sobe apanhando, Focus sobe acertando, Aether regenera. Cada classe *joga* diferente, não só tem números diferentes.
2. **Warden desde o dia 1.** O original demorou a ter healer decente e as dungeons viraram corrida de poção.
3. **Reset de atributos pago mas barato** (1 vez grátis a cada 10 níveis). O original punia experimentação.

---

## 2. COMBATE

**Original:** joystick virtual + botão de ataque + 4 slots de skill com cooldown, auto-targeting.

**Aqui:** igual na estrutura, **muito melhor na sensação**.

```
[joystick]                        [skill1] [skill2]
  esquerda                        [skill3] [ATAQUE]
                                    direita — zona do polegar
```

### Especificação
- Ataque básico: combo de 3 golpes, terceiro com knockback
- 4 slots ativos + 1 ultimate (carrega em combate)
- Auto-target: cliente escolhe o alvo visual, **servidor valida a colisão**
- Dodge roll com i-frames de 300 ms, cooldown 4 s

### 🔼 Melhorias — aqui é onde o jogo ganha ou perde

O original era de 2015 e o combate parecia. Estas são todas de **código**, custo de arte zero:

| Técnica | Efeito | Custo |
|---|---|---|
| **Hit stop 60 ms** | congela tudo no impacto. É o segredo do "peso" | trivial |
| **Flash branco no inimigo** | 80 ms, confirma o acerto | trivial |
| **Screen shake escalado** | 2px normal, 8px crítico, 20px ultimate | trivial |
| **Números de dano com curva** | sobem, desaceleram, somem. Crítico maior e amarelo | trivial |
| **Telegrafia de boss** | decal vermelho no chão 900 ms antes | baixo |
| **Cancelamento de animação** | pode cancelar recovery com dodge | médio |
| **Input buffer 150 ms** | toque no fim da animação registra | médio |
| **Slow-mo no último kill** | 0.35× por 400 ms quando limpa a horda | baixo |

> **Se o combate não estiver gostoso com cubos brancos, não vai ficar gostoso com arte bonita.** Reserve 2 semanas só para iterar o *feel* na Etapa T4.

---

## 3. CAMPANHA E ZONAS

**Original:** campanha single-player, zonas como Luxis City, Death Desert, Burning Moor. Demônios apareciam nas zonas em janelas de meia hora.

**Aqui:** 3 zonas no lançamento.

| Zona | Níveis | Tema |
|---|---|---|
| **Solhaven** | 1–15 | cidade-bastião, hub social, tutorial |
| **The Ashen Reach** | 12–28 | planície queimada pela Praga |
| **Duskmire Deep** | 25–40 | pântano subterrâneo, ninho da corrupção |

~25 quests de história + diárias/semanais.

### 🔼 Melhorias
1. **Tutorial de 4 minutos, pulável.** O original enterrava o jogador em texto. Você aprende jogando: move, bate, usa skill, pega loot, sobe de nível. Fim.
2. **Demon Raids viram eventos flexíveis.** O original abria só na meia hora cheia. Aqui: 3 janelas por dia, cada uma de 2 h, e você pode **estocar até 2 tentativas** perdidas. Respeita quem trabalha.
3. **Quest tracking na tela** com seta e distância. Nunca "vá procurar".

---

## 4. DUNGEONS CO-OP

**Original:** grupos de 4, mapas labirínticos, hordas até a sala do chefe.

**Aqui:** idêntico, com geração por seed.

- 8 dungeons × 3 dificuldades (Normal / Heroic / Nightmare)
- 4 jogadores, 8–14 minutos
- Layout gerado com **seed compartilhada** (mesmo mapa para os 4)
- 3 tentativas diárias por dificuldade

### 🔼 Melhorias
1. **Matchmaking por papel.** Fila entra como tank/healer/dps. O original virava 4 DPS morrendo no boss.
2. **Reconexão em 90 s** volta pra mesma sala, mesmo progresso. Queda de 4G no Brasil é regra, não exceção.
3. **Loot pessoal, não disputado.** Cada jogador vê o próprio drop. Mata o "ninja looting" — a maior fonte de briga em ARPG co-op.
4. **Sala de boss com fase de checkpoint.** Wipe volta pra fase, não pro início. O original fazia refazer 10 minutos de horda.

---

## 5. FORJA — EQUIPAMENTO E ENHANCEMENT

**Original:** níveis de +enhance, fragmentos, craft na mochila.

**Aqui:** 9 slots, afixos aleatórios, upgrade +0 a +15.

```
ItemDefinition   → o que o item É        (do CSV de conteúdo)
ItemInstance     → o que AQUELE rolou    (afixos, upgrade)
```

Raridade: `COMMON` → `UNCOMMON` → `RARE` → `EPIC` → `LEGENDARY`
Afixos por raridade: 0 / 1 / 2 / 3 / 4

### 🔼 Melhorias — a parte mais importante do documento

O enhancement do original era o clássico chinês predatório: falha, **destrói o item**, e você compra pedra de proteção com dinheiro real. Isso é desenhado para machucar.

| Original | Aqui |
|---|---|
| Falha destrói o item | **Nunca destrói.** Falha nunca perde o item |
| Falha volta o nível | **+0 a +9 nunca cai.** +10 a +15 cai 1 nível no máximo |
| Sem piso | **Piso garantido:** 5 falhas seguidas = próximo é sucesso automático |
| Taxa oculta | **Taxa exibida na tela** antes de confirmar |
| Proteção paga com dinheiro | Proteção comprável com **ouro** (moeda de jogo) |

**Por que isso é melhor comercialmente, não só eticamente:** enhancement destrutivo gera picos de receita e churn massivo. Jogador que perde um lendário +12 desinstala e posta print no Reddit. Progressão previsível retém — e retenção é o que paga a conta.

**Transferência de afixos:** você pode mover os afixos de um item velho para um novo do mesmo slot, pagando ouro. O original te forçava a recomeçar do zero a cada upgrade de tier.

---

## 6. GUILDAS

**Original:** guildas com guerra (o jogo virou "Guild War").

**Aqui:** guildas no lançamento, guerra na v2.0.

- 30 membros (sobe com nível da guilda)
- Ranks: Leader / Officer / Member
- Tesouro coletivo, contribuição individual rastreada
- Bônus passivo: +XP, +ouro, escalando com nível

### 🔼 Melhorias
1. **Guilda dormente é liberada.** Líder inativo 21 dias → oficial mais ativo assume automático. O original tinha guildas mortas travadas para sempre.
2. **Contribuição decai.** Peso maior nos últimos 30 dias, para não travar ranking com veterano ausente.
3. **Guilda cross-facção.** Amigo não fica preso ao alinhamento errado.

---

## 7. SOCIAL

**Original:** chat em tempo real, voice chat, comunidade in-game.

**Aqui:** chat, correio, amigos, bloqueio. **Sem voice no v1** — custo alto, moderação impossível, baixo retorno.

Canais: Global · Guilda · Grupo · Sussurro · Sistema

### 🔼 Melhorias
1. **Filtro de palavrão por idioma** — três listas separadas (pt/es/en). Palavrão em português não é palavrão em espanhol.
2. **Denúncia em 2 toques** com contexto capturado automaticamente.
3. **Chat translation opcional** — jogador brasileiro e argentino no mesmo grupo. É o diferencial mais forte que você pode ter na América do Sul.
4. **Correio com anexo expira em 30 dias**, com aviso.

---

## 8. LIVEOPS — O RITMO DIÁRIO

**Original (reconstruído dos guias):** reset às 23h. Arena com 10 tentativas grátis. Ruins of Wyrm com modo solo (dia todo) e modo equipe (só 18h–22h). Demon Raids na meia hora cheia.

**Aqui:** mesmo ritmo, **sem a tirania do relógio**.

| Atividade | Quando | Recompensa |
|---|---|---|
| Login diário | reset 09:00 UTC | ouro, gemas, materiais |
| 3 dungeons | qualquer hora | XP, loot |
| Quests diárias (5) | qualquer hora | XP, ouro |
| **Rift Surge** | 3 janelas × 2 h | XP alto, materiais raros |
| Expedição | passiva, 4/8/12 h | materiais |
| Evento semanal | fim de semana | cosmético exclusivo |

### 🔼 Melhorias
1. **Tentativas acumulam até 2 dias.** O original zerava tudo à meia-noite — quem trabalha perdia sempre. Isso sozinho melhora retenção D7 mais que qualquer feature nova.
2. **Reset em UTC, exibido em hora local.** Brasil, Argentina, Chile e Colômbia cruzam 3 fusos. Ver "reset em 4h32" resolve.
3. **Catch-up para quem volta.** Ausente 7 dias? Ganha bônus de XP por 3 dias. O original punia quem sumia — o que garantia que não voltasse.

---

## 9. LOJA E MOEDAS

**Original:** gemas premium, roleta de mercenários (gacha), pacotes.

**Aqui:** três moedas.

| Moeda | Ganha | Gasta |
|---|---|---|
| **Gold** | jogando | forja, reparo, mercado |
| **Gems** | compra + eventos | cosmético, conveniência, invocação |
| **Honor** | PvP (v2.0) | equipamento PvP |

### 🔼 Melhorias
1. **P2W com F2P viável — ver Parte E5 para a especificação completa.** Pagante avança 3–5× mais rápido; F2P consegue tudo, só demora. Whale precisa de F2P na base, senão fica sozinho e para de pagar.
2. **Battle Pass** com trilha grátis generosa. Modelo comprovado, previsível, sem gacha.
3. **Taxas de drop públicas** em qualquer invocação. Regulação está apertando, e transparência converte melhor.
4. **Pity duro:** 60 invocações garante lendário. Contador visível.
5. **Limite de gasto** configurável pelo próprio jogador. Protege quem precisa, e protege você juridicamente.

---

## 12. COMPANIONS (ex-Mercenários) — o sistema mais complexo

**Original (dos guias):** raridade por cor (branco → verde → azul → roxo → laranja → dourado). Roxo-S tinha 2 skills. Sistema de "Pactos". Fragmentos que viram equipamento via craft. Enhancement próprio. **Herança** — transferir investimento para outro mercenário. Arena of Mercenary. Bounty Appointment.

**Aqui:** mesma arquitetura, nomes novos.

```
Companion
├── Raridade:  COMMON → UNCOMMON → RARE → EPIC → LEGENDARY
├── Estrelas:  1★ a 6★ (fragmentos duplicados sobem estrela)
├── Nível:     próprio, limitado pelo nível do jogador
├── Skills:    1 skill (RARE) · 2 skills (EPIC+)
├── Bond:      substitui o "Pacto" — bônus por combinação temática
└── Equipment: 3 slots próprios, craft com fragmentos
```

- 2 Companions ativos ao mesmo tempo
- IA simples: seguir, atacar alvo do jogador, usar skill no cooldown

### 🔼 Melhorias
1. **Herança melhorada.** No original você recuperava parte. Aqui: **100% do investimento** (nível, estrelas, equipamento) transfere para outro Companion da mesma raridade, pagando ouro. Investir num Companion nunca é decisão errada.
2. **Fragmentos de qualquer Companion viram moeda universal.** Duplicata inútil deixa de existir.
3. **Companion tem papel de combate visível** (tank/dps/support) e o jogo sugere composição.
4. **Invocação com pity e taxas públicas** (ver Loja).

---

## 15–16. FAMILIARS E MOUNTS

**Original:** sistema de dragões como pets que davam habilidades. Montarias (ex.: Infernal Manticore).

**Aqui:**
- **Familiars** — companheiro passivo, dá bônus de atributo + 1 habilidade. Evolui com itens.
- **Mounts** — velocidade de movimento fora de combate, puramente cosmético em combate.

### 🔼 Melhorias
1. **Mount não dá stat.** No original virava paywall de poder. Aqui é velocidade + visual — vende igual e não quebra o balanceamento.
2. **Familiar tem personalidade visível:** segue, reage a loot raro, comemora no boss. Apego emocional retém mais que +5 de força.

---

## 10, 11, 13, 14 — SISTEMAS DE APOIO

**The Spire** (ex-Illusionary Palaces): torre infinita, 1 jogador, andar N tem dificuldade escalada. Checkpoint a cada 10. Ranking semanal. *Melhoria:* progresso salva no andar, não zera a run inteira.

**Vanity** (ex-Costumes): skin visual sem stat, slot separado do equipamento. *Melhoria:* tingimento com paleta de cores — dobra o valor percebido sem arte nova.

**Expeditions** (ex-Treasure Hunting): envia Companions em missão de 4/8/12 h, volta com materiais. Joga offline. *Melhoria:* notificação push quando termina — reengajamento gratuito.

**Codex** (ex-Collection Gallery): catálogo de monstros, itens e lore. Completar dá bônus permanente pequeno. *Melhoria:* o Codex é onde vive a sua lore original — transforma coleção em narrativa.

---

## 17–19. PvP (v2.0 — depois do D7 provado)

**Arena** — 1v1 e 3v3, 10 tentativas diárias, MMR, temporadas. *Melhoria:* equipamento **normalizado** na Arena. Vence quem joga melhor, não quem gastou mais. Isso mantém o PvP vivo depois do mês 2.

**World Bosses** — boss gigante, dezenas de jogadores, mecânica de AoE e posicionamento. *Melhoria:* recompensa por participação em faixas, não só por dano. O original dava tudo ao top-10 e os outros paravam de aparecer.

**Faction War** — Ironvow vs Ashenfold, captura de pontos, temporada de 2 semanas. *Melhoria:* balanceamento automático — facção minoritária ganha bônus de recompensa. Sem isso, uma facção domina e a outra esvazia. Foi o que matou o PvP do original.

---

## 📅 ORDEM DE CONSTRUÇÃO

```
v1.0  Classes(4) · Combate · Campanha · Dungeons · Forja
      Guildas · Social · LiveOps · Loja
      ↓ prove D7 ≥ 25% antes de continuar
v1.1  The Spire · Vanity
v1.2  Companions · Expeditions · Codex
v1.3  Familiars · Mounts · nível 50
v2.0  Arena · World Bosses · Faction War · Market · nível 60
```

> **Por que Companions só na v1.2:** é o sistema mais complexo do jogo (invocação, estrelas, equipamento próprio, herança, IA). Construir isso antes do combate básico estar gostoso é a forma mais rápida de queimar 4 meses.

---

## ✅ AS 10 MELHORIAS QUE MAIS IMPORTAM

Se você fizer só isso, já é um jogo melhor que o original:

1. **Enhancement nunca destrói item** — a mudança de maior impacto em retenção
2. **Hit stop, screen shake, números de dano** — o combate parece 10 anos mais novo, custo zero de arte
3. **Tentativas diárias acumulam 2 dias** — respeita quem trabalha
4. **Loot pessoal** — acaba com briga em grupo
5. **Gemas não compram poder** — a economia sobrevive ao mês 3
6. **Herança de Companion 100%** — investir nunca é errado
7. **Equipamento normalizado na Arena** — PvP não morre
8. **Reconexão em 90 s** — 4G brasileiro
9. **Taxas de drop públicas + pity** — confiança e conformidade
10. **Três idiomas de verdade** — o original nunca teve pt-BR. Este é o seu maior diferencial em SA.

---

## 🎯 O QUE VOCÊ REALMENTE AMAVA

Não era "Luxis". Era entrar numa dungeon com três pessoas, limpar a horda, abrir a sala do chefe e ver o loot cair.

**Isso está inteiro neste documento e é 100% seu para reconstruir.**


---

# PARTE D — PERSONAGEM

# David, the Last Shieldbearer

> **ID canônico:** `npc_david` · `companion_david`
> **Classe:** Vanguard · **Facção:** Ironvow · **Papel:** mentor do tutorial → primeiro Companion
> **Nota de produção:** personagem baseado no criador do jogo. Não renomear sem consultá-lo.

---

## O conceito

David estava em Solhaven quando A Ruptura veio. Ele não impediu — ninguém impediu. Mas quando a poeira baixou e os outros fugiram ou morreram, ele ficou. Levantou o portão de novo. Depois o muro. Depois convenceu os primeiros a voltarem.

Ele não é o herói da profecia. É o sujeito que **ficou e reconstruiu**.

Quando o jogador chega a Solhaven, David é o primeiro rosto que vê. Ele não pergunta quem você é. Entrega um escudo e diz para ficar atrás dele.

> **Por que ele funciona:** todo ARPG tem o mentor poderoso que te salva. David é o oposto — ele é *cansado*. Não te salva; te ensina a não precisar dele. É uma figura mais rara e muito mais memorável.

### Aparência
Meia-idade, barba grisalha por fazer, cicatriz vertical na sobrancelha esquerda. Armadura Ironvow remendada — placas de eras diferentes, consertadas por ele mesmo. O escudo é grande demais, gasto no centro de tanto uso.

**Detalhe de silhueta:** ele carrega o escudo nas costas mesmo fora de combate. Nunca larga. É o que o torna reconhecível a 40 metros num celular.

---

## Personalidade

| É | Não é |
|---|---|
| Seco, econômico nas palavras | Rude ou amargo |
| Prático — resolve, não filosofa | Sábio místico que fala por enigmas |
| Protetor sem ser paternal | Superprotetor |
| Humor discreto, quase invisível | Comic relief |
| Cansado, mas nunca desiste | Trágico ou derrotado |

**Regra de escrita:** frases curtas. David nunca usa duas orações quando uma resolve. Quando ele fala uma frase longa, o jogador percebe que aquilo importa.

---

## Papel no jogo

### Fase 1 — Tutorial (minutos 0–4)
Ensina mover, atacar, usar habilidade, pegar loot, subir de nível. Não explica com texto — **luta ao seu lado e você imita**.

### Fase 2 — Campanha (níveis 1–40)
Fica em Solhaven. Dá as quests principais. Some por três capítulos no meio do ato 2 — e volta ferido, sem explicar onde esteve.

### Fase 3 — Companion (v1.2)
Primeiro Companion desbloqueado, **de graça**, ao terminar a campanha. Raridade EPIC, papel Tank.

> **Por que essa estrutura:** o jogador convive com ele por 40 níveis antes de poder usá-lo. Quando finalmente desbloqueia, não é "ganhei um tank" — é "ele voltou".

---

## Kit de habilidades (Vanguard)

| Skill | ID | Efeito | CD |
|---|---|---|---|
| **Bulwark** | `van_bulwark` | Escudo à frente, bloqueia 80% do dano frontal por 3 s | 12 s |
| **Ground Break** | `van_groundbreak` | Golpe no chão, stun em área de 4 m por 1,5 s | 18 s |
| **Draw the Line** | `van_drawline` | Puxa até 6 inimigos num raio de 8 m (taunt) | 20 s |
| **Hold** *(ultimate)* | `van_hold` | Imóvel por 5 s. Aliados num raio de 6 m tomam 60% menos dano | 90 s |

**`Hold` é a assinatura dele.** Ele planta o escudo e não sai. Todo o kit diz a mesma coisa: *fico entre você e aquilo*.

---

## Falas — chaves de localização

Formato pronto para `content/source/dialogue.csv`. Ver Seção 3 do BLUEPRINT (ICU, gênero, plural).

### Primeiro encontro
```
npc.david.first_meet.01
  pt-BR  Você chegou andando. Isso já é mais do que a maioria consegue.
  es-419 Llegaste caminando. Eso ya es más de lo que logra la mayoría.
  en-US  You walked in. That's more than most manage.

npc.david.first_meet.02
  pt-BR  Pega. É pesado. Vai ser pesado por um tempo.
  es-419 Toma. Es pesado. Va a serlo por un tiempo.
  en-US  Take it. It's heavy. It'll stay heavy for a while.

npc.david.first_meet.03
  pt-BR  Fica atrás de mim até aprender a não precisar.
  es-419 Quédate detrás de mí hasta que aprendas a no necesitarlo.
  en-US  Stay behind me until you learn not to need to.
```

### Tutorial de combate
```
npc.david.tutorial.move
  pt-BR  Anda. Parado você é alvo.
  es-419 Muévete. Quieto eres un blanco.
  en-US  Move. Standing still makes you a target.

npc.david.tutorial.dodge
  pt-BR  Vermelho no chão quer dizer sai. Não bloqueia. Sai.
  es-419 Rojo en el suelo significa muévete. No bloquees. Muévete.
  en-US  Red on the ground means move. Don't block. Move.

npc.david.tutorial.done
  pt-BR  Serve.
  es-419 Sirve.
  en-US  That'll do.
```
> `tutorial.done` é a maior elogio dele no jogo inteiro. Nunca escreva David dizendo "muito bem".

### Sobre A Ruptura
```
npc.david.sundering.01
  pt-BR  Perguntam o que eu vi. Vi o céu rachar. Todo mundo viu.
  es-419 Preguntan qué vi. Vi el cielo partirse. Todos lo vieron.
  en-US  People ask what I saw. I saw the sky split. Everyone did.

npc.david.sundering.02
  pt-BR  A pergunta certa é o que a gente fez depois. Eu levantei o portão.
  es-419 La pregunta correcta es qué hicimos después. Yo levanté la puerta.
  en-US  The right question is what we did after. I put the gate back up.

npc.david.sundering.03
  pt-BR  Sozinho, no começo. Depois não.
  es-419 Solo, al principio. Después no.
  en-US  Alone, at first. Not after.
```

### Como Companion (v1.2)
```
companion.david.summon
  pt-BR  Mesmo lugar de sempre. Atrás de mim.
  es-419 El mismo lugar de siempre. Detrás de mí.
  en-US  Same place as always. Behind me.

companion.david.ultimate
  pt-BR  Aqui eles não passam.
  es-419 De aquí no pasan.
  en-US  They don't get past here.

companion.david.player_revive
  pt-BR  Levanta. Ainda não acabou.
  es-419 Levántate. Todavía no termina.
  en-US  Get up. It's not over.

companion.david.boss_defeated
  pt-BR  Você não precisou de mim nessa.
  es-419 En esta no me necesitaste.
  en-US  You didn't need me for that one.
```

### O retorno (fim do ato 2 — a fala que importa)
```
npc.david.return
  pt-BR  Achei que não voltava. Voltei.
         Solhaven ainda tá de pé porque alguém teimou.
         Vai ser você da próxima vez.
  es-419 Pensé que no volvía. Volví.
         Solhaven sigue en pie porque alguien se puso terco.
         La próxima vez vas a ser tú.
  en-US  I didn't think I'd make it back. I did.
         Solhaven's still standing because somebody was stubborn about it.
         Next time that's you.
```

---

## Regras de escrita para a IA

1. **Máximo 12 palavras por linha.** Se passar, corte.
2. **Nunca "muito bem", "excelente", "parabéns".** O elogio máximo dele é *"serve"*.
3. **Nunca explica lore sem ser perguntado.**
4. **Nunca chama o jogador de "escolhido", "herói" ou "salvador".** Ele diz "você".
5. **Sem enigma, sem profecia, sem metáfora.** Ele fala o que é.
6. **Uma vez por ato** ele pode falar três frases seguidas. Só uma vez. É o que dá peso.

---

## Easter egg (opcional)

No portão de Solhaven, uma placa gasta:

```
prop.solhaven_gate.plaque
  pt-BR  Reconstruído por D. — e por quem ficou.
  es-419 Reconstruido por D. — y por quienes se quedaron.
  en-US  Rebuilt by D. — and by those who stayed.
```

Sem explicação no jogo. Quem entender, entendeu.


---

# PARTE E — LORE, HERÓIS E MONETIZAÇÃO

> Decisões do criador registradas em 20/08/2026:
> **P2W sim, com caminho F2P viável** · **pt-BR é o idioma padrão** · **David é herói jogável**
> · **8 classes seguindo o molde da referência** · **lore 100% original**

---

# E1. LORE ORIGINAL

## O mundo: Aurethia

Aurethia foi construída sobre uma coisa que ninguém devia ter tocado.

Nas profundezas do continente corre o **Aether** — não magia, mas o material de que a realidade é feita. Por mil anos, os **Aetherwrights** aprenderam a puxar fios dele para erguer cidades flutuantes, curar pragas e parar guerras. Cada fio puxado era um fio a menos.

Ninguém percebeu que estavam desfiando o tecido.

## A Ruptura (The Sundering)

Há trinta anos, o tecido cedeu.

Não houve exército, não houve vilão. Numa manhã de outono o céu **rachou** — uma fenda de horizonte a horizonte, e por ela desceu o silêncio. Onde o Aether foi drenado, a realidade não se sustenta: pedras caem para cima, mortos andam sem lembrar que morreram, e a paisagem se repete como um pensamento travado.

Chamam isso de **A Praga (The Blight)**.

As sete cidades flutuantes caíram. Das doze grandes casas restaram três. E o continente ficou dividido entre o que ainda é real e o que está esquecendo como ser.

## A Coroa Oca (The Hollow Crown)

Da fenda veio algo com forma de rei e nada dentro.

A Coroa Oca não conquista — ela **descosta**. Onde passa, as coisas param de ter sido. Vilarejos somem dos mapas e das memórias ao mesmo tempo. Não se sabe se é criatura, consequência ou a própria Ruptura tentando terminar o serviço.

Ela não fala. Nunca falou.

## Solhaven, a última que ficou de pé

Solhaven não era importante. Era uma cidade-forte de fronteira, feia e mal-acabada, construída sobre rocha em vez de Aether — porque era pobre demais para pagar Aetherwrights.

Foi exatamente isso que a salvou.

Quando as sete cidades caíram do céu, Solhaven continuou onde sempre esteve. Os sobreviventes vieram, e ela virou o último lugar real do continente. As muralhas foram levantadas por gente que não sabia levantar muralhas.

> **O tema do jogo:** o que sobrevive não é o mais poderoso. É o que estava assentado em algo real.

## A Vigília (The Vigil)

Não é uma ordem sagrada. É o que sobrou.

Ferreiros, desertores, acadêmicos, ladrões. Gente que ficou quando ficar não fazia sentido. A Vigília não tem profecia, não tem escolhido, não tem deus. Tem um portão e uma lista de quem ainda está vivo.

**O juramento**, dito em voz baixa, sem cerimônia:
> *"Eu fico."*

## As duas facções

Trinta anos depois, a Vigília se dividiu — não por ódio, mas por discordância honesta sobre como se salva um mundo.

### ⚔️ Ironvow — "Segure a linha"
Reconstruir devagar, com o que é real. Nada de Aether. Se a humanidade levar duzentos anos para se recuperar, que leve. **Foi o Aether que quebrou o mundo; usá-lo de novo é repetir o erro.**
Disciplina, muralha, paciência. Ouro e aço-azul.

### 🔥 Ashenfold — "Não temos duzentos anos"
A Praga avança mais rápido do que a reconstrução. **Usar o Aether contra a Praga é a única chance** — e sim, isso custa. Os Ashenfold pagam com a própria vida útil: cada feitiço queima anos deles.
Pragmatismo, sacrifício, urgência. Carmim e cinza.

> **Nenhum dos dois está errado.** É o que faz a Guerra de Facções funcionar por anos em vez de meses.

## Os três atos

| Ato | Zona | O que acontece |
|---|---|---|
| **I** | Solhaven & Ashen Reach | A Praga chega ao portão. Você aprende a segurar. |
| **II** | Duskmire Deep | Descobre-se que a Praga é *dirigida*. Alguém está guiando. |
| **III** | The Riven Sky | Subir até a fenda. Descobrir que a Coroa Oca já foi humana. |

**A revelação do Ato III:** a Coroa Oca foi o último Aetherwright — o que tentou costurar o tecido de volta sozinho e virou parte do buraco. Ele não é o vilão. É a última pessoa que tentou consertar tudo.

---

# E2. AS 8 CLASSES

## ⚠️ Nota de pesquisa

Confirmei **4 das 8** classes da referência nos vídeos do canal oficial: **Warrior, Mage, Archer, Priest**. As outras 4 não estão documentadas em nenhuma fonte que sobreviveu. As marcadas com 🔧 são reconstrução seguindo o molde padrão de ARPG asiático (tank / dps físico / dps mágico / suporte × 2 variações).

## Estrutura: Herói = Classe

Como na referência, o jogador **escolhe um herói**, e cada herói É uma classe. Não é criação de personagem livre — é seleção de personagem com identidade própria, arte própria e história própria.

| # | Herói | Classe | Papel | Atributo | Recurso | Fase |
|---|---|---|---|---|---|---|
> ⚠️ **ESTRUTURA REVISADA — ver Parte F1.** As "8 classes" são **4 classes base × 2 especializações
> escolhidas no nível 20**. É o modelo "mago vira mago de fogo ou de gelo" que o gênero usa,
> e explica o número 8 anunciado pela referência.

| Classe base | Herói | Spec A (nv20) | Spec B (nv20) |
|---|---|---|---|
| ⚔️ **Warrior** | **David** | Guardian (tank) | Ravager (bruiser) |
| 🔥 **Mage** | **Mireya** | Pyromancer (fogo/área) | Cryomancer (gelo/controle) |
| 🏹 **Ranger** | **Tobias** | Marksman (distância) | Bladedancer (corpo a corpo) |
| ✨ **Priest** | **Serina** | Lightbearer (cura) | Soulbinder (sombra/invocação) |

**Lançamento com as 4 classes base e todas as 8 especializações.** A especialização não é
conteúdo cortado — ela É o conteúdo do nível 20 ao 40.

## Recurso próprio por classe

Isto é o que faz cada herói *jogar* diferente, não só ter números diferentes:

| Recurso | Como enche | Consequência de design |
|---|---|---|
| **Resolve** | apanhando | David quer estar no meio da horda |
| **Aether** | regenera com o tempo | Mireya e Yara gerenciam janelas |
| **Focus** | acertando | Tobias precisa manter ritmo, não pode kitar demais |
| **Grace** | curando aliados | Serina é premiada por curar, não por poupar |
| **Momentum** | movendo-se | Corvin morre se parar |
| **Fury** | perdendo HP | Halvard é mais forte quanto pior está |
| **Essence** | invocações morrendo | Nael sacrifica o que cria |

---

# E3. DAVID — HERÓI JOGÁVEL

> **Personagem baseado no criador do jogo. Não renomear.**

**David** · Warden · Ironvow · O primeiro herói disponível, gratuito, sem gacha.

## História

David tinha vinte e dois anos quando o céu rachou. Não era soldado — era pedreiro em Solhaven.

Quando as sete cidades caíram e os sobreviventes chegaram aos milhares, alguém precisava levantar muralha. Ele sabia levantar muralha. Levantou. Depois pegou um escudo porque a muralha não bastava, e nunca mais largou.

Trinta anos depois ele ainda está no portão.

Nunca foi escolhido, nunca teve profecia. É o sujeito que **ficou** — e é por isso que Solhaven existe.

### Aparência
Cinquenta e poucos. Barba grisalha por fazer, cicatriz vertical na sobrancelha esquerda. Armadura Ironvow remendada com placas de eras diferentes, consertadas por ele mesmo. O escudo é grande demais e gasto no centro.

**Silhueta:** carrega o escudo nas costas mesmo fora de combate. É o que o torna reconhecível a 40 metros num celular de 6 polegadas.

### Como ele fala
Frases curtas. Nunca duas orações quando uma resolve. Sem enigma, sem profecia, sem metáfora. O maior elogio dele no jogo inteiro é **"Serve."** — nunca "muito bem".

Uma vez por ato ele pode falar três frases seguidas. Só uma vez. É o que dá peso.

## Kit — Warden

| Skill | ID | Efeito | CD |
|---|---|---|---|
| **Bulwark** | `war_bulwark` | Escudo frontal, bloqueia 80% do dano por 3 s. Gera Resolve ao bloquear | 12 s |
| **Ground Break** | `war_groundbreak` | Golpe no chão, stun em área de 4 m por 1,5 s | 18 s |
| **Draw the Line** | `war_drawline` | Puxa até 6 inimigos num raio de 8 m | 20 s |
| **Hold** ⭐ | `war_hold` | Imóvel 5 s. Aliados em 6 m tomam 60% menos dano | 90 s |

**`Hold` é a assinatura.** Ele planta o escudo e não sai. Todo o kit diz a mesma coisa: *fico entre você e aquilo*.

## Falas (chaves de localização)

```
hero.david.select
  pt-BR  Eu fico.
  es-419 Yo me quedo.
  en-US  I'll stay.

hero.david.tutorial.move
  pt-BR  Anda. Parado você é alvo.
  es-419 Muévete. Quieto eres un blanco.
  en-US  Move. Standing still makes you a target.

hero.david.tutorial.dodge
  pt-BR  Vermelho no chão quer dizer sai. Não bloqueia. Sai.
  es-419 Rojo en el suelo significa muévete. No bloquees. Muévete.
  en-US  Red on the ground means move. Don't block. Move.

hero.david.tutorial.done
  pt-BR  Serve.
  es-419 Sirve.
  en-US  That'll do.

hero.david.ultimate
  pt-BR  Aqui eles não passam.
  es-419 De aquí no pasan.
  en-US  They don't get past here.

hero.david.revive_ally
  pt-BR  Levanta. Ainda não acabou.
  es-419 Levántate. Todavía no termina.
  en-US  Get up. It's not over.

hero.david.boss_defeated
  pt-BR  Serve. Próximo.
  es-419 Sirve. El siguiente.
  en-US  That'll do. Next.

hero.david.act3_gate                    ← as três frases do Ato III
  pt-BR  Trinta anos nesse portão. Achei que ia morrer nele.
         Solhaven tá de pé porque alguém teimou.
         Agora é você.
  es-419 Treinta años en esta puerta. Pensé que moriría en ella.
         Solhaven sigue en pie porque alguien se puso terco.
         Ahora te toca a ti.
  en-US  Thirty years at this gate. Thought I'd die on it.
         Solhaven's still standing because somebody was stubborn.
         Now it's you.
```

### Easter egg — placa no portão de Solhaven
```
prop.solhaven_gate.plaque
  pt-BR  Levantado por D. — e por quem ficou.
  es-419 Levantada por D. — y por quienes se quedaron.
  en-US  Raised by D. — and by those who stayed.
```
Sem explicação no jogo. Quem entender, entendeu.

---

# E4. MAPAS

Seguindo o molde da referência: **hub social + zonas de campo com raids por horário + dungeons instanciadas + torre**.

| Mapa | Tipo | Nível | Equivalente estrutural |
|---|---|---|---|
| **Solhaven** | Hub social, 40 jogadores | — | cidade-capital |
| **The Ashen Reach** | Campo aberto + raids | 12–28 | zona de deserto |
| **Duskmire Deep** | Campo aberto + raids | 25–40 | zona de pântano |
| **The Riven Sky** | Campo aberto + raids | 38–50 | zona final (v1.3) |
| **8 Dungeons** | Instanciado, 4 jogadores | 10–40 | co-op dungeons |
| **The Spire** | Torre infinita, solo | 20+ | Illusionary Palaces |
| **Faction Front** | PvP massivo | 40+ | campo de batalha (v2.0) |

**Rift Surge** (equivalente aos Demon Raids): eventos de campo que abrem em 3 janelas de 2 h por dia, em locais fixos de cada zona, com requisito de nível. **Tentativas perdidas acumulam até 2 dias** — a mudança mais importante em relação à referência, que zerava tudo à meia-noite.

---

# E5. MONETIZAÇÃO — P2W COM F2P VIÁVEL

## O princípio econômico (não é ética, é negócio)

**Whale paga para se sentir poderoso em relação a outros jogadores.**

Se os F2P saem, o whale fica sozinho num servidor vazio e para de pagar. **Os F2P são o conteúdo dos whales.** Por isso o F2P precisa ser viável — não por bondade, mas porque é a base da receita.

A regra que os jogos bem-sucedidos seguem:

> **F2P consegue tudo. Só que 3 a 5 vezes mais devagar.**
> Nunca "F2P não consegue". Sempre "F2P demora".

Abaixo de 3× o pagante não sente vantagem. Acima de 5× o F2P desiste. **A faixa 3–5× é onde o dinheiro está.**

## As camadas de gasto

### 1. VIP (progressão por gasto acumulado)
VIP 1 a 15, sobe conforme o total gasto. Cada nível dá benefícios permanentes: mais tentativas diárias, mais slots, auto-combate, mais espaço na mochila, bônus de XP.

> **Regra:** VIP dá **conveniência e velocidade**, e stats pequenos. Nunca desbloqueia conteúdo que o F2P não pode acessar.

### 2. Battle Pass (o carro-chefe)
Temporada de 6 semanas, trilha grátis + trilha premium. **A trilha grátis precisa ser generosa** — é o que ensina o jogador que vale a pena voltar todo dia. R$ 24,90 é o ponto ideal para o Brasil.

### 3. Gacha de Heróis e Companions
Invocação com moeda premium.

**Obrigatório:**
- Taxas de drop **públicas** na tela de invocação
- **Pity duro:** 60 invocações garante lendário, contador visível
- **Pity suave:** taxa sobe progressivamente após a 40ª
- Fragmentos de duplicatas viram moeda universal — nada é lixo
- **Heróis também caem de eventos** — F2P consegue, demora

### 4. Forja e Enhancement
Aqui é onde o P2W mais aparece, e onde mais se erra.

| ❌ O que mata o jogo | ✅ O que funciona |
|---|---|
| Falha **destrói** o item | Falha nunca destrói |
| Sem piso de proteção | 5 falhas seguidas = próxima é sucesso |
| Proteção só com dinheiro real | Proteção também com ouro (mais cara) |
| Taxa oculta | Taxa na tela antes de confirmar |

> Jogador que perde um lendário +12 desinstala e posta print. Isso custa mais em churn do que rende em receita. **Venda velocidade de upgrade, não risco de perda.**

### 5. Conveniência
Refil de energia, tentativas extras de dungeon, expedições instantâneas, slots de inventário, reset de atributos. Receita alta, impacto zero no balanceamento.

### 6. Cosmético
Vanity, mounts, efeitos de habilidade, emblema de guilda. **Mount não dá stat** — só velocidade fora de combate e visual. Vende igual e não quebra nada.

## O que o F2P TEM garantido

Escrito como contrato. Se quebrar isso, o modelo desmorona:

- ✅ Todos os 8 heróis (via evento, fragmento ou moeda de jogo)
- ✅ Toda a campanha e todas as dungeons
- ✅ Equipamento lendário (droppa, só é mais raro)
- ✅ Guilda, chat, social, tudo
- ✅ Battle Pass grátis com recompensa real
- ✅ Arena com **equipamento normalizado** — no PvP competitivo vence quem joga melhor

> A Arena normalizada é o que segura o F2P por meses. Ele perde no PvE aberto para o whale, mas na Arena está em pé de igualdade. **É a válvula de escape que impede a debandada.**

## Ritmo de receita

| Momento | Oferta | Preço |
|---|---|---|
| Primeira compra | pacote iniciante 3× valor | R$ 4,90 |
| Dia 3 | Battle Pass | R$ 24,90 |
| Dia 7 | pacote de herói | R$ 49,90 |
| Semanal | fundo de gemas | R$ 9,90 |
| Mensal | assinatura (gemas diárias + VIP) | R$ 29,90 |
| Evento | pacote limitado | R$ 99,90+ |

**Preço regional obrigatório.** R$ 4,90 no Brasil não é US$ 0,99 na Argentina. Defina tier por país em moeda local, com números redondos culturalmente.

## Limite de gasto

Ferramenta de **limite mensal autoimposto** nas configurações. Protege quem precisa e protege você juridicamente — a regulação de loot box está apertando no Brasil e na América Latina.

---

# E6. IDIOMA

## pt-BR é o padrão

```typescript
// schema.prisma — já configurado
preferredLoc  Locale  @default(PT_BR)
```

**Fluxo:**
1. Primeiro boot → detecta o idioma do aparelho
2. `pt` ou desconhecido → **pt-BR**
3. `es` (qualquer variante) → **es-419**
4. `en` → **en-US**
5. Jogador pode trocar a qualquer momento nas configurações

**Ao trocar, muda TUDO na hora:** UI, nome de item, descrição de skill, diálogo, mensagem de sistema, nome de monstro, quest, e-mail no jogo. Sem reiniciar o app.

Isso funciona porque o servidor manda **chave**, nunca frase (Parte B, Seção 3.2). O cliente resolve no locale ativo.

**Ficha da loja e suporte também nos 3 idiomas.** Não adianta o jogo estar em espanhol se o atendimento responde só em português.


---

# PARTE F — CLASSES, ESPECIALIZAÇÕES, COMBATE E BESTIÁRIO

> **Números validados por simulação.** Todas as fórmulas abaixo passaram em 11 verificações
> automáticas no `balance-sim.mjs`. Não são chute — foram testadas do nível 10 ao 60.
> Rode `node balance-sim.mjs` antes de mexer em qualquer constante.

---

# F1. O SISTEMA DE ESPECIALIZAÇÃO

## A descoberta

A referência anunciava **8 classes**. Confirmei apenas 4 nos vídeos oficiais: Warrior, Mage, Archer, Priest.

A explicação mais provável — e a estrutura que vamos usar — é a clássica do gênero:

> **4 classes base × 2 especializações = 8 classes**

É exatamente o modelo "mago vira mago de fogo ou mago de gelo". Resolve o número 8, é como o gênero faz, e dá muito mais profundidade que 8 classes soltas.

## Como funciona

```
Nível 1 ──────────────► escolhe a CLASSE BASE (4 opções)
                        joga com o kit compartilhado
                              │
Nível 20 ─────────────► escolhe a ESPECIALIZAÇÃO (2 opções)
                        desbloqueia 4 skills exclusivas
                        muda visual da armadura
                        muda o recurso
                              │
Nível 40 ─────────────► ASCENSÃO
                        ultimate exclusiva da especialização
```

**Reespecialização:** paga com gemas ou item de evento. **Uma vez grátis** ao chegar no nível 40 — o jogador precisa poder errar sem se arrepender para sempre.

## As 4 classes base e suas 8 especializações

| Classe base | Herói | Spec A (nível 20) | Spec B (nível 20) |
|---|---|---|---|
| ⚔️ **Warrior** | **David** | **Guardian** — tank puro, escudo, taunt | **Ravager** — bruiser, dano por HP perdido |
| 🔥 **Mage** | **Mireya** | **Pyromancer** — fogo, dano em área, queimadura | **Cryomancer** — gelo, controle, lentidão |
| 🏹 **Ranger** | **Tobias** | **Marksman** — alvo único, crítico, distância | **Bladedancer** — corpo a corpo, mobilidade |
| ✨ **Priest** | **Serina** | **Lightbearer** — cura, escudo, purificação | **Soulbinder** — sombra, DoT, invocação |

> **Lançamento:** as 4 classes base, todas as 8 especializações. Não é conteúdo cortado — a especialização É o conteúdo do nível 20 ao 40.

## Recurso por especialização

O que faz cada spec *jogar* diferente, não só ter números diferentes:

| Spec | Recurso | Enche | Consequência de design |
|---|---|---|---|
| Guardian | **Resolve** | bloqueando e apanhando | quer estar no meio da horda |
| Ravager | **Fury** | perdendo HP | mais forte quanto pior está |
| Pyromancer | **Aether** | regenera | gerencia janelas de burst |
| Cryomancer | **Frost** | acertando congelados | premiado por manter controle |
| Marksman | **Focus** | acertando à distância | não pode kitar demais |
| Bladedancer | **Momentum** | movendo-se | morre se parar |
| Lightbearer | **Grace** | curando aliados | premiado por curar, não por poupar |
| Soulbinder | **Essence** | invocações morrendo | sacrifica o que cria |

---

# F2. FÓRMULAS DE COMBATE (autoritativas)

> ⚠️ **Todo cálculo abaixo roda no servidor.** O cliente só prediz visualmente.

## Atributos

```
Por nível:  +1 em STR, AGI, INT, VIT (automático)
            +5 pontos livres (jogador distribui)
Base nv1:   10 em cada
```

| Atributo | Efeito |
|---|---|
| **STR** | +2 Dano Físico · +1 Armadura |
| **AGI** | +0,15% Chance de Crítico · +0,5% Velocidade de Ataque |
| **INT** | +2 Dano Mágico · +15 Recurso Máximo |
| **VIT** | +25 HP Máximo |

## Derivados

```
maxHp        = 100 + VIT × 25 + nível × 5
physDamage   = 10 + STR × 2
magicDamage  = 10 + INT × 2
armor        = STR × 1 + armadura do equipamento
critChance   = min(0.05 + AGI × 0.0015, 0.75)     ← teto 75%
critMult     = 1.5
atkSpeed     = 1.0 + AGI × 0.005
```

## Mitigação de armadura — a fórmula mais importante

```
K = 50 + 15 × nível_do_atacante
mitigação = min(armadura / (armadura + K), 0.75)
```

**Por que essa curva:** nunca chega a 100% (imortalidade), nunca fica negativa, e o `K` crescente força o jogador a continuar buscando equipamento melhor — armadura antiga perde valor naturalmente sem precisar nerfar nada.

Comportamento validado:

| Armadura | Nv10 | Nv30 | Nv60 |
|---|---|---|---|
| 0 | 0,0% | 0,0% | 0,0% |
| 120 | 37,5% | 19,4% | 11,2% |
| 500 | 71,4% | 50,0% | 34,5% |
| 1000 | 75,0% | 66,7% | 51,3% |
| ∞ | 75,0% | 75,0% | 75,0% |

## Dano final

```
raw          = danoBase × multiplicadorDaSkill
apósArmadura = raw × (1 − mitigação)
final        = max(1, round(apósArmadura × (crítico ? 1.5 : 1)))
```

**`max(1, ...)` é obrigatório.** Dano zero trava a percepção do jogador — ele acha que o jogo bugou.

## Monstros

```
HP    = (80 + nível × 45)  × [comum 1 · elite 8 · boss 200]
Dano  = (8 + nível × 3.2)  × [comum 1 · elite 1.8 · boss 3.2]
Armad = (nível × 2)        × [comum 1 · elite 1.5 · boss 2.2]
```

## Resultados validados

**TTK contra comum** (alvo 2–5 s, hack'n'slash precisa ser rápido):

| Spec | Nv10 | Nv30 | Nv60 |
|---|---|---|---|
| Pyromancer | 2,5s | 2,3s | 2,0s |
| Marksman | 3,1s | 2,4s | 1,9s |
| Guardian | 4,6s | 4,3s | 3,9s |

**Boss com grupo** (1 tank + 1 healer + 2 DPS ≈ 2,5× o DPS solo):

| Nível | Duração |
|---|---|
| 20 | 230s |
| 40 | 181s |
| 60 | 144s |

**Sobrevivência no nível 60** (hits até morrer contra comum):

| Spec | EHP | Hits |
|---|---|---|
| Guardian | 8.477 | 42 |
| Lightbearer | 6.221 | 31 |
| Ravager | 5.577 | 28 |
| Pyromancer | 3.861 | 19 |
| Marksman | 2.543 | 13 |
| Bladedancer | 2.476 | 12 |

Tank tem **2,20×** o EHP do DPS. DPS causa **1,91×** o dano do tank. Papéis distintos e legíveis.

---

# F3. ÁRVORES DE HABILIDADE

Cada especialização tem **4 skills exclusivas + 1 ultimate**. As 3 primeiras skills são da classe base, compartilhadas entre as duas specs.

## ⚔️ Warrior — base
| Skill | Nv | Efeito | CD |
|---|---|---|---|
| `war_cleave` | 1 | Golpe em arco, 3 alvos | 6s |
| `war_charge` | 4 | Avança 8m, empurra | 14s |
| `war_groundbreak` | 8 | Stun em área 4m, 1,5s | 18s |

### Guardian (nv20)
| Skill | Nv | Efeito | CD |
|---|---|---|---|
| `gua_bulwark` | 20 | Bloqueia 80% frontal por 3s, gera Resolve | 12s |
| `gua_drawline` | 24 | Puxa 6 inimigos em 8m (taunt) | 20s |
| `gua_ironskin` | 30 | +40% armadura por 8s | 25s |
| `gua_retaliate` | 36 | Devolve 30% do dano bloqueado por 6s | 22s |
| `gua_hold` ⭐ | 40 | Imóvel 5s. Aliados em 6m tomam −60% dano | 90s |

### Ravager (nv20)
| Skill | Nv | Efeito | CD |
|---|---|---|---|
| `rav_bloodthirst` | 20 | +2% dano por 10% HP perdido | passiva |
| `rav_rend` | 24 | Sangramento, 40% do dano em 6s | 10s |
| `rav_frenzy` | 30 | +50% vel. ataque por 6s, custa 10% HP | 24s |
| `rav_execute` | 36 | Dano ×3 em alvo abaixo de 25% HP | 15s |
| `rav_lastStand` ⭐ | 40 | 8s sem poder morrer. Ao fim, cura o dano evitado ×0,3 | 120s |

## 🔥 Mage — base
| Skill | Nv | Efeito | CD |
|---|---|---|---|
| `mag_bolt` | 1 | Projétil perfurante | 4s |
| `mag_blink` | 4 | Teleporte 6m, i-frames 200ms | 12s |
| `mag_barrier` | 8 | Escudo de 15% do HP máx por 6s | 20s |

### Pyromancer (nv20)
`pyr_fireball` (área 5m) · `pyr_ignite` (queimadura, empilha 3×) · `pyr_wall` (parede de fogo 8s) · `pyr_detonate` (consome queimaduras, dano ×2)
⭐ `pyr_meteor` (nv40) — impacto de 10m, 900ms de telegrafia, dano massivo

### Cryomancer (nv20)
`cry_shard` (lentidão 30%) · `cry_frostNova` (congela 2s em 6m) · `cry_glacier` (parede sólida bloqueia caminho) · `cry_shatter` (dano ×2,5 em congelado)
⭐ `cry_absoluteZero` (nv40) — congela tudo em 12m por 4s

## 🏹 Ranger — base
`ran_shot` · `ran_roll` (dodge com i-frames 300ms) · `ran_trap` (armadilha, root 2s)

### Marksman (nv20)
`mrk_pierce` (atravessa 4 alvos) · `mrk_mark` (alvo marcado toma +25%) · `mrk_volley` (5 flechas em área) · `mrk_steady` (parado = +40% crítico)
⭐ `mrk_deadeye` (nv40) — 6s de crítico garantido

### Bladedancer (nv20)
`bld_dash` (atravessa e corta) · `bld_spin` (área, gera Momentum) · `bld_shadowstep` (atrás do alvo) · `bld_bleed` (empilha sangramento)
⭐ `bld_thousandCuts` (nv40) — 12 golpes em 3s, invulnerável durante

## ✨ Priest — base
`pri_heal` · `pri_smite` (dano sagrado) · `pri_cleanse` (remove 1 debuff)

### Lightbearer (nv20)
`lit_sanctuary` (cura em área) · `lit_aegis` (escudo em aliado) · `lit_revive` (revive com 30% HP) · `lit_blessing` (+15% dano do grupo 10s)
⭐ `lit_dawnbreak` (nv40) — cura total do grupo + imunidade 3s

### Soulbinder (nv20)
`sou_drain` (dano + cura 40%) · `sou_summon` (2 servos por 20s) · `sou_curse` (−30% armadura) · `sou_harvest` (mata servo, cura grupo)
⭐ `sou_reaping` (nv40) — invoca 6 servos por 15s

---

# F4. BESTIÁRIO

## O princípio

Mesma **função** no jogo, criatura **diferente**. Se lá tinha uma aranha vermelha de veneno, aqui tem uma **Viúva de Cinzas** — mesma função (veneno, teia, emboscada), identidade própria dentro da lore de Aurethia.

Nada é copiado. Tudo é reconstruído a partir da Praga e do Aether.

## Ashen Reach — planície queimada (nv 12–28)

| ID | Nome | Tier | Comportamento |
|---|---|---|---|
| `mob_ash_widow` | **Ash Widow** | comum | Aranha de cinzas. Teia que lentifica, veneno empilhável |
| `mob_husk_walker` | **Husk Walker** | comum | Corpo sem memória. Lento, muito HP, cerca em grupo |
| `mob_ember_hound` | **Ember Hound** | comum | Matilha de 4. Rápido, salta, morre fácil |
| `mob_cinder_shade` | **Cinder Shade** | comum | Some e reaparece atrás do jogador |
| `mob_rustplate` | **Rustplate Sentinel** | comum | Armadura antiga possuída. Alta armadura, lento |
| `mob_widow_matron` | **Widow Matron** | elite | Invoca 3 Ash Widows a cada 15s |
| `mob_pyre_knight` | **Pyre Knight** | elite | Investida em linha, telegrafia 900ms |
| 👑 `boss_ashen_warden` | **The Ashen Warden** | boss | 3 fases: melee → invoca → área total |

## Duskmire Deep — pântano subterrâneo (nv 25–40)

| ID | Nome | Tier | Comportamento |
|---|---|---|---|
| `mob_bog_leech` | **Bogleech** | comum | Drena HP e cura a si |
| `mob_fungal_thrall` | **Fungal Thrall** | comum | Explode ao morrer, área de veneno |
| `mob_mire_stalker` | **Mire Stalker** | comum | Emboscada, invisível até 3m |
| `mob_drowned_choir` | **Drowned Choir** | comum | Grupo de 3 que se cura mutuamente. Matar junto |
| `mob_gloom_weaver` | **Gloomweaver** | comum | Reduz visão do jogador em 40% |
| `mob_rot_colossus` | **Rot Colossus** | elite | Área ao pisar, deixa poças |
| `mob_hollow_priest` | **Hollow Priest** | elite | Escuda outros inimigos. Prioridade de alvo |
| 👑 `boss_mother_mire` | **Mother of the Mire** | boss | Enche a sala de poça. Plataformas seguras diminuem |

## The Riven Sky — a fenda (nv 38–50, v1.3)

| ID | Nome | Tier | Comportamento |
|---|---|---|---|
| `mob_void_moth` | **Voidmoth** | comum | Voa, imune a área terrestre |
| `mob_unwritten` | **The Unwritten** | comum | Sem forma fixa. Muda resistência a cada 10s |
| `mob_gravebound` | **Gravebound** | comum | Ressuscita 1× se não for morto com crítico |
| `mob_aether_leech` | **Aether Leech** | comum | Drena recurso, não HP |
| `mob_seam_ripper` | **Seam Ripper** | elite | Abre fendas que puxam o jogador |
| 👑 `boss_hollow_crown` | **The Hollow Crown** | boss final | 5 fases. A arena se desfaz progressivamente |

## Regras de design de monstro

1. **Todo ataque tem telegrafia.** Comum 400ms, elite 700ms, boss 900ms. Decal vermelho no chão.
2. **Nenhum inimigo comum causa mais de 12% do HP do jogador** por golpe. Morte tem que ser acúmulo de erros, nunca surpresa.
3. **Todo grupo tem prioridade de alvo clara** — o healer, o invocador, o que escuda. Ensina o jogador a pensar.
4. **Máximo 14 skinned meshes na tela** no tier LOW (Parte B, Seção 4.2). Horda grande = inimigos simples.
5. **Boss muda de fase em 70% e 35% do HP**, com janela de 2s onde fica vulnerável. É o momento de burst.

---

# F5. LOOT E RARIDADE

```
COMMON     cinza     0 afixos    peso 1000
UNCOMMON   verde     1 afixo     peso 400
RARE       azul      2 afixos    peso 120
EPIC       roxo      3 afixos    peso 25
LEGENDARY  laranja   4 afixos    peso 3
```

Chance base de lendário: **0,19%** por drop. Com bônus de dificuldade Nightmare: **0,57%**.

> As cores são convenção do gênero. **NÃO INOVE AQUI** — o jogador de ARPG lê essas cores sem pensar.

**Afixos rolam dentro de um range definido no `ItemDefinition.baseStats`.** Um item EPIC com 3 afixos ruins pode valer menos que um RARE bem rolado — é isso que faz o loot continuar interessante no nível 60.

---

# F6. CHECKLIST PARA A IA

Antes de implementar qualquer coisa desta parte:

- [ ] Rodou `node balance-sim.mjs` e passou nas 11 verificações
- [ ] Todo cálculo de dano está no servidor, nunca no cliente
- [ ] `max(1, dano)` aplicado — nunca dano zero
- [ ] Mitigação usa a fórmula `armadura/(armadura+K)`, nunca subtração direta
- [ ] Teto de 75% em mitigação e em crítico
- [ ] Toda skill tem `cooldownMs` validado no servidor
- [ ] Todo monstro tem telegrafia antes do ataque
- [ ] Cores de raridade vêm de `design-tokens.json`
- [ ] Nome de monstro e skill é chave de localização, nunca string
