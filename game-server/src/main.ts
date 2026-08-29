import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { FastifyAdapter, NestFastifyApplication } from "@nestjs/platform-fastify";
import { AppModule } from "./app.module.js";

// ARMADILHA nº 7: BigInt quebra JSON.stringify.
// Sem isto, qualquer rota que retorne ouro/gemas lança TypeError.
// Consequência: valores monetários chegam ao cliente como STRING. C# faz long.Parse().
(BigInt.prototype as any).toJSON = function () { return this.toString(); };

async function bootstrap() {
  const app = await NestFactory.create<NestFastifyApplication>(AppModule, new FastifyAdapter());
  await app.listen(Number(process.env.PORT ?? 3000), "0.0.0.0");
  console.log(`game-server on :${process.env.PORT ?? 3000}`);
}
bootstrap();
