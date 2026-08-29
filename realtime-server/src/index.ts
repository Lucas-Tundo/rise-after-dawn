// ⚠️ ARMADILHA nº 2 — ESTA LINHA TEM QUE SER A PRIMEIRA DO ARQUIVO.
// @colyseus/schema 3.x usa Symbol.metadata. Sem o polyfill o servidor SOBE,
// os clientes CONECTAM, e só quebra ao enviar o primeiro estado:
//   TypeError: Cannot read properties of undefined (reading 'Symbol(Symbol.metadata)')
(Symbol as any).metadata ??= Symbol.for("Symbol.metadata");

import { Server } from "colyseus";
import { WebSocketTransport } from "@colyseus/ws-transport";
import { DungeonRoom } from "./rooms/DungeonRoom.js";

const PORT = Number(process.env.PORT ?? 2567);

// ⚠️ ARMADILHA nº 5: NÃO passe { port } aqui — a porta vai no listen().
const gameServer = new Server({ transport: new WebSocketTransport() });

gameServer.define("dungeon", DungeonRoom);

await gameServer.listen(PORT);
console.log(`realtime-server on :${PORT} | tick 20 Hz`);
