using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using Colyseus;
using UnityEngine;
using RiseAfterDawn.Client.States;

namespace RiseAfterDawn.Client.Networking
{
    public sealed class T8NetworkManager : MonoBehaviour
    {
        [Header("Conexão")]
        [SerializeField] private string serverUrl = "ws://localhost:2567";
        [SerializeField] private string realtimeToken = string.Empty;
        [SerializeField] private string characterId = string.Empty;

        [Header("Movimento")]
        [SerializeField] private Transform playerPrefab;
        [SerializeField] private T8VirtualJoystick joystick;
        [SerializeField] private T8RemotePlayerInterpolator remoteInterpolator;
        [SerializeField] private float moveSpeed = 6f;
        [SerializeField] private float reconciliationTolerance = 0.15f;
        [SerializeField] private float inputSendInterval = 0.05f;

        private ColyseusClient client;
        private ColyseusRoom<DungeonState> room;
        private Transform localPlayer;
        private readonly List<InputCommand> pendingInputs = new List<InputCommand>();
        private readonly Stopwatch stopwatch = Stopwatch.StartNew();
        private Vector3 predictedPosition;
        private float sendTimer;
        private uint nextSequence;
        private uint lastAcknowledgedSequence;
        private int reconciliationCount;
        private int receivedTickCount;
        private double lastRttMs;

        public double LastRttMs => lastRttMs;
        public uint ServerTick => room == null ? 0 : room.State.tick;
        public int ReconciliationCount => reconciliationCount;
        public int ReceivedTickCount => receivedTickCount;
        public float ReconciliationRate => receivedTickCount == 0
            ? 0f
            : (float)reconciliationCount / receivedTickCount;

        private async void Start()
        {
            if (string.IsNullOrWhiteSpace(realtimeToken))
            {
                UnityEngine.Debug.LogError("debug.network.missing_realtime_token");
                return;
            }

            try
            {
                client = new ColyseusClient(serverUrl);
                var options = new Dictionary<string, object>
                {
                    ["token"] = realtimeToken
                };

                room = await client.JoinOrCreate<DungeonState>("dungeon", options);
                room.OnStateChange += OnStateChange;
                room.OnMessage<CorrectionMessage>("correction", OnCorrection);
                if (remoteInterpolator != null)
                {
                    remoteInterpolator.Initialize(this);
                }
                UnityEngine.Debug.Log("debug.network.connected");
            }
            catch (Exception error)
            {
                UnityEngine.Debug.LogException(error);
            }
        }

        private void Update()
        {
            if (room == null || localPlayer == null)
            {
                return;
            }

            var direction = ReadMoveInput();
            var dt = Mathf.Min(Time.unscaledDeltaTime, 0.1f);
            predictedPosition += new Vector3(direction.x, 0f, direction.y) * moveSpeed * dt;
            localPlayer.position = predictedPosition;

            sendTimer += Time.unscaledDeltaTime;
            if (sendTimer >= inputSendInterval)
            {
                sendTimer = 0f;
                SendInput(dt);
            }
        }

        private Vector2 ReadMoveInput()
        {
            var value = joystick == null ? Vector2.zero : joystick.Value;
            if (value.sqrMagnitude < 0.001f)
            {
                value = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
            }

            return Vector2.ClampMagnitude(value, 1f);
        }

        private void SendInput(float dt)
        {
            var command = new InputCommand
            {
                Sequence = ++nextSequence,
                Direction = ReadMoveInput(),
                DeltaTime = dt,
                SentAtMs = stopwatch.Elapsed.TotalMilliseconds,
                Position = predictedPosition
            };
            pendingInputs.Add(command);

            room.Send("input", new Dictionary<string, object>
            {
                ["seq"] = command.Sequence,
                ["x"] = command.Position.x,
                ["z"] = command.Position.z,
                ["dt"] = command.DeltaTime
            });
        }

        private void OnStateChange(DungeonState state, bool isFirstState)
        {
            receivedTickCount++;
            if (remoteInterpolator != null)
            {
                remoteInterpolator.ApplySnapshot(state, room.SessionId);
            }

            var serverPlayer = state.players[room.SessionId];
            if (serverPlayer == null)
            {
                return;
            }

            if (localPlayer == null)
            {
                localPlayer = playerPrefab == null
                    ? GameObject.CreatePrimitive(PrimitiveType.Cube).transform
                    : Instantiate(playerPrefab);
                predictedPosition = new Vector3(serverPlayer.x, 0f, serverPlayer.z);
                localPlayer.position = predictedPosition;
            }

            if (serverPlayer.lastSeq <= lastAcknowledgedSequence)
            {
                return;
            }

            lastAcknowledgedSequence = serverPlayer.lastSeq;
            for (var i = pendingInputs.Count - 1; i >= 0; i--)
            {
                var input = pendingInputs[i];
                if (input.Sequence <= lastAcknowledgedSequence)
                {
                    var rtt = stopwatch.Elapsed.TotalMilliseconds - input.SentAtMs;
                    lastRttMs = rtt;
                    pendingInputs.RemoveAt(i);
                }
            }

            var authoritative = new Vector3(serverPlayer.x, 0f, serverPlayer.z);
            if (Vector3.Distance(authoritative, predictedPosition) > reconciliationTolerance)
            {
                reconciliationCount++;
                predictedPosition = authoritative;
                ResimulatePendingInputs();
                localPlayer.position = predictedPosition;
            }
        }

        private void OnCorrection(CorrectionMessage correction)
        {
            if (correction.seq <= lastAcknowledgedSequence)
            {
                return;
            }

            lastAcknowledgedSequence = correction.seq;
            for (var i = pendingInputs.Count - 1; i >= 0; i--)
            {
                if (pendingInputs[i].Sequence <= correction.seq)
                {
                    pendingInputs.RemoveAt(i);
                }
            }

            reconciliationCount++;
            predictedPosition = new Vector3(correction.x, 0f, correction.z);
            ResimulatePendingInputs();
            if (localPlayer != null)
            {
                localPlayer.position = predictedPosition;
            }
        }

        private void ResimulatePendingInputs()
        {
            foreach (var input in pendingInputs)
            {
                predictedPosition += new Vector3(input.Direction.x, 0f, input.Direction.y)
                    * moveSpeed
                    * input.DeltaTime;
            }
        }

        private async void OnDestroy()
        {
            if (room != null)
            {
                await room.Leave();
            }
        }

        [Serializable]
        private sealed class InputCommand
        {
            public uint Sequence;
            public Vector2 Direction;
            public float DeltaTime;
            public double SentAtMs;
            public Vector3 Position;
        }

        [Serializable]
        private sealed class CorrectionMessage
        {
            public uint seq;
            public float x;
            public float z;
        }
    }
}
