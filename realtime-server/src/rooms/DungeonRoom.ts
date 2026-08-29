import { Room, Client } from "colyseus";
import { DungeonState, Player } from "../schema/DungeonState.js";

const TICK_HZ = 20;
const TICK_MS = 1000 / TICK_HZ;
const MAX_SPEED = 6.0;      // m/s
const TOLERANCE = 1.15;     // margem para jitter de rede

export class DungeonRoom extends Room<DungeonState> {
  maxClients = 4;

  onCreate() {
    this.state = new DungeonState();
    this.setSimulationInterval(() => { this.state.tick++; }, TICK_MS);

    this.onMessage("input", (client, msg: { seq: number; x: number; z: number; dt: number }) => {
      const p = this.state.players.get(client.sessionId);
      if (!p) return;
      if (msg.seq <= p.lastSeq) return;                      // anti-replay

      const dist = Math.hypot(msg.x - p.x, msg.z - p.z);
      if (dist > MAX_SPEED * msg.dt * TOLERANCE) {           // ANTI-SPEEDHACK
        client.send("correction", { seq: msg.seq, x: p.x, z: p.z });
        return;                                              // descarta o input
      }
      p.x = msg.x; p.z = msg.z; p.lastSeq = msg.seq;
    });
  }

  onJoin(client: Client, opts: { characterId?: string }) {
    const p = new Player();
    p.characterId = opts?.characterId ?? "anon";
    this.state.players.set(client.sessionId, p);
  }

  onLeave(client: Client) {
    this.state.players.delete(client.sessionId);
  }
}
