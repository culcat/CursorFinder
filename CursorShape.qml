import QtQuick
import QtQuick.Shapes
import qs.Commons as Commons

Item {
  id: root

  property int baseSize: 24
  property real cursorScale: 1.0
  property string cursorStyle: "macos" // "macos" | "theme" | "inverted"
  property bool showHalo: false

  width: baseSize
  height: baseSize
  transformOrigin: Item.TopLeft
  scale: cursorScale

  readonly property color fillColor: {
    if (cursorStyle === "theme") return Commons.Color.accent
    if (cursorStyle === "inverted") return "#f5f5f7"
    return "#111114"
  }

  readonly property color outlineColor: {
    if (cursorStyle === "inverted") return "#111114"
    return "#ffffff"
  }

  // Optional subtle locator halo around the tip
  Rectangle {
    visible: root.showHalo
    x: -width / 2
    y: -height / 2
    width: root.baseSize * 1.35
    height: width
    radius: width / 2
    color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.16)
    border.width: 1.2
    border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.65)
    antialiasing: true
  }

  // Drop shadow for contrast on any background
  Shape {
    x: 0.9
    y: 1.4
    width: root.baseSize
    height: root.baseSize
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 1.6
      strokeColor: Qt.rgba(0, 0, 0, 0.28)
      fillColor: Qt.rgba(0, 0, 0, 0.28)
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.RoundCap

      startX: 0; startY: 0
      PathLine { x: 0; y: root.baseSize * 0.78 }
      PathLine { x: root.baseSize * 0.21; y: root.baseSize * 0.59 }
      PathLine { x: root.baseSize * 0.35; y: root.baseSize * 0.90 }
      PathLine { x: root.baseSize * 0.47; y: root.baseSize * 0.84 }
      PathLine { x: root.baseSize * 0.33; y: root.baseSize * 0.53 }
      PathLine { x: root.baseSize * 0.57; y: root.baseSize * 0.53 }
      PathLine { x: 0; y: 0 }
    }
  }

  // Main high-DPI vector macOS pointer arrow
  Shape {
    x: 0
    y: 0
    width: root.baseSize
    height: root.baseSize
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 1.5
      strokeColor: root.outlineColor
      fillColor: root.fillColor
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.RoundCap

      startX: 0; startY: 0
      PathLine { x: 0; y: root.baseSize * 0.78 }
      PathLine { x: root.baseSize * 0.21; y: root.baseSize * 0.59 }
      PathLine { x: root.baseSize * 0.35; y: root.baseSize * 0.90 }
      PathLine { x: root.baseSize * 0.47; y: root.baseSize * 0.84 }
      PathLine { x: root.baseSize * 0.33; y: root.baseSize * 0.53 }
      PathLine { x: root.baseSize * 0.57; y: root.baseSize * 0.53 }
      PathLine { x: 0; y: 0 }
    }
  }
}
