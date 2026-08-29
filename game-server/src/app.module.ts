import { Module, Controller, Get } from "@nestjs/common";

@Controller("api/v1")
class BootstrapController {
  // Toda sessão começa aqui, ANTES do login. Ver Parte B, Seção 5.6.
  @Get("bootstrap")
  bootstrap() {
    return {
      minClientVersion: "1.0.0",
      latestClientVersion: "1.0.0",
      protocolVersion: 1,
      addressablesCatalogUrl: null,
      maintenance: { active: false, messageKey: null, etaUtc: null },
      locales: ["pt-BR", "es-419", "en-US"],
      defaultLocale: "pt-BR",
    };
  }
}

@Module({ controllers: [BootstrapController] })
export class AppModule {}
