# Rise After Dawn

ARPG isométrico hack'n'slash mobile · dungeons co-op de 4 jogadores · servidor autoritativo
Brasil primeiro (pt-BR padrão) → AR/CL/CO/PE → NA

## Stack

| Camada | Tecnologia |
|---|---|
| Cliente | Unity 6 LTS · URP |
| API / estado | NestJS 11.2.1 + Fastify 5.12.1 |
| Tempo real | **Colyseus 0.16.5** (não 0.17) |
| ORM | Prisma 7.9.1 |
| Banco | Supabase — **região São Paulo** |
| Cache / salas | Redis 7 |
| Portal | Next.js 16 |

## Começar

```bash
docker compose up -d

cd game-server
npm i --save-exact prisma@7.9.1 @prisma/client@7.9.1 @prisma/adapter-pg@7.9.1 pg@8.23.0 dotenv
npm i -D --save-exact tsx@4.23.12 typescript @types/node
cp .env.example .env      # preencha as URLs do Supabase
npx prisma migrate dev --name init
npx prisma generate
```

**Aceite:** 33 tabelas e 20 enums criados.

```bash
node scripts/balance-sim.mjs     # 11 verificações de combate
node scripts/validate-brand.mjs  # marca e assets de loja
```

## Documentos

| Arquivo | O que é |
|---|---|
| `ARCHITECTURE.md` | **Fonte única da verdade.** 6 partes, tudo do projeto |
| `AGENTS.md` | Regras para a IA (Cursor lê automaticamente) |
| `PROMPT_CURSOR.md` | Prompt de arranque para colar no Cursor |
| `design-tokens.json` | Cor, tipografia, espaçamento — fonte única |

## ⚠️ Antes de tudo

A **Etapa T8** é portão de risco: 4 celulares reais em 4G, um cubo e um monstro.
Se a latência reprovar, a arquitetura muda. Faça antes de escrever sistema de jogo.
