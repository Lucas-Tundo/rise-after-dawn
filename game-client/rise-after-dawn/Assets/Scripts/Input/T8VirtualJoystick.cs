using UnityEngine;
using UnityEngine.EventSystems;

namespace RiseAfterDawn.Client.Networking
{
    public sealed class T8VirtualJoystick : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
    {
        [SerializeField] private RectTransform area;
        [SerializeField] private RectTransform knob;
        [SerializeField] private float radius = 80f;

        public Vector2 Value { get; private set; }

        public void OnPointerDown(PointerEventData eventData)
        {
            UpdateValue(eventData);
        }

        public void OnDrag(PointerEventData eventData)
        {
            UpdateValue(eventData);
        }

        public void OnPointerUp(PointerEventData eventData)
        {
            Value = Vector2.zero;
            if (knob != null)
            {
                knob.anchoredPosition = Vector2.zero;
            }
        }

        private void UpdateValue(PointerEventData eventData)
        {
            if (area == null)
            {
                return;
            }

            if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(
                    area,
                    eventData.position,
                    eventData.pressEventCamera,
                    out var localPoint))
            {
                return;
            }

            var offset = Vector2.ClampMagnitude(localPoint, radius);
            Value = offset / Mathf.Max(radius, 0.001f);
            if (knob != null)
            {
                knob.anchoredPosition = offset;
            }
        }
    }
}
