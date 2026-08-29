using UnityEngine;

namespace RiseAfterDawn.Client.Networking
{
    public sealed class T8DebugOverlay : MonoBehaviour
    {
        [SerializeField] private T8NetworkManager networkManager;
        [SerializeField] private bool visible = true;
        [SerializeField] private Rect screenRect = new Rect(16f, 16f, 520f, 96f);

        private void OnGUI()
        {
            if (!visible || networkManager == null)
            {
                return;
            }

            var reconciliationRate = networkManager.ReconciliationRate * 100f;
            var text =
                $"debug.network.rtt_ms: {networkManager.LastRttMs:0} | " +
                $"debug.network.server_tick: {networkManager.ServerTick}\n" +
                $"debug.network.reconciliation_rate: {reconciliationRate:0.00}% | " +
                $"debug.network.reconciliation_count: {networkManager.ReconciliationCount}";

            GUI.Label(screenRect, text);
        }
    }
}
