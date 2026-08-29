# Pipeline de conteúdo

`source/` é onde o designer edita (chave + pt-BR).
`translated/` é onde o tradutor devolve (es-419, en-US).

`build-locales.ts` gera o seed do Postgres e as StringTables da Unity.

**O build FALHA (exit 1) se:**
- uma chave existe em pt-BR mas falta em es-419 ou en-US
- um placeholder ICU (`{count}`, `{playerName}`) some ou muda de nome
- uma string traduzida passa de 140% do tamanho da versão em inglês

Arquivos esperados: `items.csv` · `skills.csv` · `monsters.csv` · `quests.csv` · `dialogue.csv`
