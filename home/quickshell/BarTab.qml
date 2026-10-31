import QtQuick
import QtQuick.Shapes

// A tab hanging from the top screen edge, flowing into it through concave shoulders.
Item {
    id: root

    default property alias content: contentRow.data
    property alias spacing: contentRow.spacing
    property int sidePadding: 10

    readonly property int shoulder: 14
    readonly property int corner: 16

    implicitWidth: contentRow.implicitWidth + (root.sidePadding + root.shoulder) * 2
    width: implicitWidth
    height: Theme.tabHeight

    Behavior on width {
        NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.base
            strokeColor: Theme.stroke
            strokeWidth: 1
            startX: 0
            startY: -2

            PathLine { x: 0; y: 0 }
            PathArc { x: root.shoulder; y: root.shoulder; radiusX: root.shoulder; radiusY: root.shoulder }
            PathLine { x: root.shoulder; y: root.height - root.corner - 1 }
            PathArc {
                x: root.shoulder + root.corner
                y: root.height - 1
                radiusX: root.corner
                radiusY: root.corner
                direction: PathArc.Counterclockwise
            }
            PathLine { x: root.width - root.shoulder - root.corner; y: root.height - 1 }
            PathArc {
                x: root.width - root.shoulder
                y: root.height - root.corner - 1
                radiusX: root.corner
                radiusY: root.corner
                direction: PathArc.Counterclockwise
            }
            PathLine { x: root.width - root.shoulder; y: root.shoulder }
            PathArc { x: root.width; y: 0; radiusX: root.shoulder; radiusY: root.shoulder }
            PathLine { x: root.width; y: -2 }
        }
    }

    Row {
        id: contentRow
        x: root.shoulder + root.sidePadding
        y: Math.round((root.height - height) / 2)
        spacing: 8
    }
}
