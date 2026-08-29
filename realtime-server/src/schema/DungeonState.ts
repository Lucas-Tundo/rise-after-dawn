import { Schema, MapSchema, type } from "@colyseus/schema";

export class Player extends Schema {
  @type("string") characterId: string = "";
  @type("float32") x: number = 0;
  @type("float32") z: number = 0;
  @type("float32") rotY: number = 0;
  @type("uint32") lastSeq: number = 0;
  @type("int32") hp: number = 100;
  @type("int32") resource: number = 0;
}

export class DungeonState extends Schema {
  @type({ map: Player }) players = new MapSchema<Player>();
  @type("uint32") tick: number = 0;
}
