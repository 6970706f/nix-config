import QtQuick

// Circular meter; value goes from 0 to 100.
Canvas {
    id: root

    property real value: 0
    property color accent: Theme.iris
    property color trackColor: Theme.raised
    property real thickness: 3

    Behavior on value {
        NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
    }

    onValueChanged: requestPaint()
    onAccentChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        const center = width / 2;
        const radius = center - root.thickness / 2 - 0.5;
        const start = -Math.PI / 2;
        const sweep = Math.max(0, Math.min(1, root.value / 100)) * Math.PI * 2;

        ctx.clearRect(0, 0, width, height);
        ctx.lineWidth = root.thickness;
        ctx.lineCap = "round";

        ctx.strokeStyle = root.trackColor.toString();
        ctx.beginPath();
        ctx.arc(center, center, radius, 0, Math.PI * 2);
        ctx.stroke();

        if (sweep > 0) {
            ctx.strokeStyle = root.accent.toString();
            ctx.beginPath();
            ctx.arc(center, center, radius, start, start + sweep);
            ctx.stroke();
        }
    }
}
