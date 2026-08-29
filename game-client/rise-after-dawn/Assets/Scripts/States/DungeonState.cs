using Colyseus.Schema;

namespace RiseAfterDawn.Client.States
{
    public partial class PlayerState : Schema
    {
        [Type(0, "string")]
        public string characterId = string.Empty;

        [Type(1, "float32")]
        public float x;

        [Type(2, "float32")]
        public float z;

        [Type(3, "float32")]
        public float rotY;

        [Type(4, "uint32")]
        public uint lastSeq;

        [Type(5, "int32")]
        public int hp = 100;

        [Type(6, "int32")]
        public int resource;
    }

    public partial class DungeonState : Schema
    {
        [Type(0, "map", typeof(MapSchema<PlayerState>))]
        public MapSchema<PlayerState> players = new MapSchema<PlayerState>();

        [Type(1, "uint32")]
        public uint tick;
    }
}
