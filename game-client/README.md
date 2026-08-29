# T8 — cliente Unity

Este diretório contém o scaffold da Etapa 0: cubo jogável, joystick virtual,
predição local, reconciliação com o estado autoritativo e interpolação dos
demais jogadores.

## Pré-requisitos

- Unity 6 LTS com URP
- Colyseus Unity SDK **0.16.x**, instalado pelo Package Manager:
  `https://github.com/colyseus/colyseus-unity3d.git#upm`
- Servidor realtime em `ws://localhost:2567`
- Um access token emitido pelo game-server e um realtime token emitido por
  `POST /api/v1/auth/realtime-token`

O repositório não contém o editor Unity nem o SDK binário. Portanto, os
critérios de 4G, RTT p95 e desempenho em aparelho LOW ainda precisam ser
executados em Unity e em quatro celulares físicos.

## Cena mínima

1. Crie um projeto Unity 6 URP.
2. Copie `Assets/Scripts` para o projeto.
3. Crie um `GameObject` vazio chamado `T8Network`.
4. Adicione `T8NetworkManager` e informe `realtimeToken`.
5. Adicione `T8DebugOverlay` ao mesmo objeto.
6. Adicione `T8VirtualJoystick` a um `Canvas` com uma área e um knob.
7. Crie um prefab simples de cubo para `playerPrefab`.
8. Gere os estados C# com os arquivos em `Assets/Scripts/States`.
9. Execute `npm run dev` em `realtime-server` e rode a cena.

O overlay usa chaves de localização (`debug.network.rtt_ms`,
`debug.network.server_tick`, `debug.network.reconciliation_rate`) para não
introduzir texto de produto hardcoded. Ele é apenas diagnóstico de
desenvolvimento e deve ser removido da build de produção.

## Aceite T8

Registre, por aparelho e por sessão em 4G:

- RTT p95 menor que 120 ms
- reconciliações abaixo de 5% dos ticks
- resposta de toque percebida como instantânea
- um aparelho tier LOW sem queda de frame relevante

Só marque a T8 como aprovada depois de preencher os resultados com quatro
aparelhos reais. O scaffold, sozinho, não prova latência de rede móvel.
