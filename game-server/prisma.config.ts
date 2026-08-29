import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations", seed: "tsx prisma/seed.ts" },
  // SUPABASE: a CLI usa a conexão DIRETA (5432).
  // Migration NÃO funciona no pooler de transação (6543) — trava sem erro.
  datasource: { url: env("DIRECT_URL") },
});
