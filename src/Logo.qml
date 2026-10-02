import QtQuick
import qs.Commons

// Three squares growing toward the top right: a small pixel becoming a large
// one. Drawn in the theme accent so the mark follows Omarchy themes; the
// same shape is share/omascayl.svg.
Canvas {
  id: root

  property real size: 32
  property color tint: Color.accent

  width: size
  height: size
  onTintChanged: requestPaint()
  onSizeChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    var u = width / 32
    ctx.reset()
    ctx.fillStyle = root.tint
    ctx.fillRect(2 * u, 24 * u, 6 * u, 6 * u)
    ctx.globalAlpha = 0.75
    ctx.fillRect(6 * u, 12 * u, 10 * u, 10 * u)
    ctx.globalAlpha = 1
    ctx.lineWidth = 2.5 * u
    ctx.strokeStyle = root.tint
    ctx.strokeRect(14.25 * u, 1.25 * u, 16.5 * u, 16.5 * u)
  }
}
