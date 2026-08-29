using System.Collections.Generic;
using UnityEngine;
using RiseAfterDawn.Client.States;

namespace RiseAfterDawn.Client.Networking
{
    public sealed class T8RemotePlayerInterpolator : MonoBehaviour
    {
        [SerializeField] private Transform remotePrefab;
        [SerializeField] private float interpolationDelay = 0.1f;

        private readonly Dictionary<string, RemoteTrack> tracks = new Dictionary<string, RemoteTrack>();
        private T8NetworkManager networkManager;

        public void Initialize(T8NetworkManager manager)
        {
            networkManager = manager;
        }

        private void Update()
        {
            if (networkManager == null)
            {
                return;
            }

            foreach (var track in tracks.Values)
            {
                if (track.Samples.Count < 2)
                {
                    continue;
                }

                var renderAt = Time.unscaledTime - interpolationDelay;
                while (track.Samples.Count >= 2 && track.Samples[1].Time <= renderAt)
                {
                    track.Samples.RemoveAt(0);
                }

                var first = track.Samples[0];
                var second = track.Samples.Count > 1 ? track.Samples[1] : first;
                var duration = Mathf.Max(second.Time - first.Time, 0.001f);
                var alpha = Mathf.Clamp01((renderAt - first.Time) / duration);
                track.Transform.position = Vector3.Lerp(first.Position, second.Position, alpha);
            }
        }

        public void ApplySnapshot(DungeonState state, string localSessionId)
        {
            var seen = new HashSet<string>();
            foreach (string sessionId in state.players.Keys)
            {
                if (sessionId == localSessionId)
                {
                    continue;
                }

                seen.Add(sessionId);
                if (!tracks.TryGetValue(sessionId, out var track))
                {
                    var instance = remotePrefab == null
                        ? GameObject.CreatePrimitive(PrimitiveType.Capsule).transform
                        : Instantiate(remotePrefab);
                    track = new RemoteTrack(instance);
                    tracks.Add(sessionId, track);
                }

                var player = state.players[sessionId];
                track.Samples.Add(new Sample
                {
                    Time = Time.unscaledTime,
                    Position = new Vector3(player.x, 0f, player.z)
                });
                while (track.Samples.Count > 8)
                {
                    track.Samples.RemoveAt(0);
                }
            }

            var removed = new List<string>();
            foreach (var key in tracks.Keys)
            {
                if (!seen.Contains(key))
                {
                    removed.Add(key);
                }
            }

            foreach (var key in removed)
            {
                Destroy(tracks[key].Transform.gameObject);
                tracks.Remove(key);
            }
        }

        private sealed class RemoteTrack
        {
            public readonly Transform Transform;
            public readonly List<Sample> Samples = new List<Sample>();

            public RemoteTrack(Transform transform)
            {
                Transform = transform;
            }
        }

        private struct Sample
        {
            public float Time;
            public Vector3 Position;
        }
    }
}
