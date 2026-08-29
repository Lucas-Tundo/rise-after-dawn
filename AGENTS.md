# Rise After Dawn — instruções para a IA

> **LEIA `ARCHITECTURE.md` ANTES DE ESCREVER QUALQUER CÓDIGO.**
> Ele é a fonte única da verdade deste projeto e tem 6 partes (A a F).
> Foi validado por execução real, não é teoria.

## Regras invioláveis

1. **Versões travadas.** Use a matriz da Parte A com `--save-exact`. Nunca `^`, nunca `@latest`, nunca `npm update`. **Colyseus é 0.16.5** — a 0.17 quebra com o cliente, já foi testado.
2. **Ordem obrigatória.** T0 → T1 → ... → T8. Cada tarefa tem critério de aceite. **Rode o teste antes de dizer que terminou.**
3. **Leia as 7 armadilhas** da Parte A antes da primeira linha de código.
4. **Não invente.** Se não está no documento, **pergunte**.
5. **Nunca hardcode texto.** Sempre chave de localização. Padrão pt-BR.
6. **Nunca cor fora de `design-tokens.json`.** Rode `node scripts/validate-brand.mjs`.
7. **Nunca calcule dano/crítico/loot/cooldown no cliente.** Servidor autoritativo.
8. **Nunca mexa em moeda fora de `$transaction`** com EconomyLedger + WalletBalance juntos.
9. **Nunca `prisma db push`.** Sempre `prisma migrate dev`.
10. **Todo import ESM local termina em `.js`**, mesmo escrevendo `.ts`.
11. **Nunca use nome, texto, asset ou lore de Clash for Dawn.** Sistemas sim (Parte C), expressão não. A lore é a da Parte E1.
12. **Todo arquivo com `@type` do Colyseus fica sob `src/`.** Fora do `include` do tsconfig os decorators não se aplicam e o erro aponta para dentro da lib.
13. **Antes de mexer em fórmula de combate**, rode `node scripts/balance-sim.mjs`. As 11 verificações têm que passar.

## Mapa do documento

| Parte | Quando ler |
|---|---|
| **A — Execução** | Antes de qualquer código |
| **B — Arquitetura** | Ao projetar um sistema |
| **C — Sistemas de jogo** | Ao implementar gameplay |
| **D — David** | Ao escrever conteúdo |
| **E — Lore, heróis, monetização** | Ao definir economia e narrativa |
| **F — Combate, classes, bestiário** | Ao implementar combate |
