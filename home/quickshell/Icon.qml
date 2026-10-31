import QtQuick

Text {
    color: Theme.text
    font.family: Theme.iconFont
    font.pixelSize: 16
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    // Grayscale edges: subpixel antialiasing tints large glyphs orange and blue.
    renderType: Text.CurveRendering
}
