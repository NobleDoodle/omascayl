import QtQuick
import qs.Commons

// Before/after viewer. Upscayl 2.x offers the same two modes:
//   slider - original on the left, result on the right of a draggable divider;
//            hovering zooms both around the pointer by `zoom`.
//   lens   - the result fills the view and a magnifier follows the pointer,
//            original in its left half, result in its right half.
// Without a result it just shows the original.
Item {
  id: root

  property string beforeSource: ""
  property string afterSource: ""
  property string mode: "slider"
  property real zoom: 1
  property real split: 0.5

  // Large results are decoded down to this box for display; the file on disk
  // keeps its full size. The lens shares the same decoded texture.
  readonly property size previewLimit: Qt.size(8192, 8192)

  signal beforeLoaded(int width, int height)

  clip: true

  readonly property bool comparing: afterSource !== "" && after.status === Image.Ready
  property bool forceHover: false     // snapshot hook: pretend the pointer is in
  readonly property bool hovering: hover.hovered || forceHover
  property point pointer: Qt.point(width / 2, height / 2)
  readonly property real zoomNow: comparing && mode === "slider" && hovering ? zoom : 1

  // Where the (centered, aspect-fit) image is painted, from the result when
  // there is one; both share an aspect ratio.
  readonly property Image geometrySource: comparing ? after : before
  readonly property real paintedW: geometrySource.paintedWidth
  readonly property real paintedH: geometrySource.paintedHeight
  readonly property real paintedX: (width - paintedW) / 2
  readonly property real paintedY: (height - paintedH) / 2

  Image {
    id: before
    anchors.fill: parent
    source: root.beforeSource
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    visible: !(root.comparing && root.mode === "lens")
    transform: Scale {
      origin.x: root.pointer.x
      origin.y: root.pointer.y
      xScale: root.zoomNow
      yScale: root.zoomNow
    }
    onStatusChanged: if (status === Image.Ready) root.beforeLoaded(implicitWidth, implicitHeight)
  }

  Item {
    id: rightPane
    x: root.mode === "lens" ? 0 : Math.round(root.width * root.split)
    width: root.width - x
    height: root.height
    clip: true
    visible: root.comparing

    Image {
      id: after
      x: -rightPane.x
      width: root.width
      height: root.height
      source: root.afterSource
      sourceSize: root.previewLimit
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      transform: Scale {
        origin.x: root.pointer.x
        origin.y: root.pointer.y
        xScale: root.zoomNow
        yScale: root.zoomNow
      }
    }
  }

  // Loading / failure notes for the result.
  Rectangle {
    anchors.centerIn: parent
    visible: root.afterSource !== "" && after.status !== Image.Ready
    width: note.implicitWidth + 2 * Style.spacing.xxl
    height: note.implicitHeight + 2 * Style.spacing.lg
    color: Util.alpha(Color.background, 0.85)
    radius: Style.cornerRadius
    border.width: 1
    border.color: Style.normalBorderColor

    Text {
      textFormat: Text.PlainText
      id: note
      anchors.centerIn: parent
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      text: after.status === Image.Error
        ? "The upscayled image is too large to preview here. Use Open Image."
        : "Loading the upscayled image..."
    }
  }

  // ---- slider ---------------------------------------------------------------------
  Item {
    id: divider
    visible: root.comparing && root.mode === "slider"
    x: Math.round(root.width * root.split) - width / 2
    y: root.zoomNow > 1 ? 0 : root.paintedY
    width: knob.width
    height: root.zoomNow > 1 ? root.height : root.paintedH

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.max(2, Style.space(2))
      height: parent.height
      color: Color.accent
    }

    Rectangle {
      id: knob
      anchors.centerIn: parent
      width: Style.space(30)
      height: width
      radius: Style.cornerRadius > 0 ? width / 2 : 0
      color: Color.background
      border.width: Math.max(2, Style.space(2))
      border.color: Color.accent

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "◀▶"
        color: Color.accent
        font.pixelSize: Style.font.caption
      }
    }
  }

  component Chip: Rectangle {
    property alias text: label.text
    width: label.implicitWidth + 2 * Style.spacing.md
    height: label.implicitHeight + 2 * Style.spacing.xs
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.8)
    border.width: 1
    border.color: Style.normalBorderColor
    Text {
      textFormat: Text.PlainText
      id: label
      anchors.centerIn: parent
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Chip {
    visible: root.comparing && root.mode === "slider"
    x: Math.max(Style.spacing.md, root.paintedX + Style.spacing.md)
    y: Math.max(Style.spacing.md, root.paintedY + Style.spacing.md)
    text: "Original"
  }

  Chip {
    visible: root.comparing && root.mode === "slider"
    x: Math.min(root.width - width - Style.spacing.md, root.paintedX + root.paintedW - width - Style.spacing.md)
    y: Math.max(Style.spacing.md, root.paintedY + Style.spacing.md)
    text: "Upscayled"
  }

  // ---- lens -----------------------------------------------------------------------
  Rectangle {
    id: lens
    readonly property real mag: 2 * root.zoom
    readonly property real fx: root.paintedW > 0 ? (root.pointer.x - root.paintedX) / root.paintedW : 0.5
    readonly property real fy: root.paintedH > 0 ? (root.pointer.y - root.paintedY) / root.paintedH : 0.5
    readonly property real bigW: root.paintedW * mag
    readonly property real bigH: root.paintedH * mag
    readonly property real half: width / 2

    visible: root.comparing && root.mode === "lens" && root.hovering
    width: Style.space(320)
    height: Style.space(220)
    x: Math.round(root.pointer.x - width / 2)
    y: Math.round(root.pointer.y - height / 2)
    color: Color.background
    border.width: Math.max(2, Style.space(2))
    border.color: Color.accent
    radius: Style.cornerRadius

    Item {
      x: lens.border.width
      y: lens.border.width
      width: lens.half - lens.border.width
      height: lens.height - 2 * lens.border.width
      clip: true
      Image {
        source: root.beforeSource
        x: lens.half - lens.fx * lens.bigW - parent.x
        y: lens.height / 2 - lens.fy * lens.bigH - parent.y
        width: lens.bigW
        height: lens.bigH
        smooth: true
        mipmap: true
      }
    }

    Item {
      x: lens.half
      y: lens.border.width
      width: lens.half - lens.border.width
      height: lens.height - 2 * lens.border.width
      clip: true
      Image {
        source: root.afterSource
        sourceSize: root.previewLimit
        x: -lens.fx * lens.bigW
        y: lens.height / 2 - lens.fy * lens.bigH - parent.y
        width: lens.bigW
        height: lens.bigH
        smooth: true
        mipmap: true
      }
    }

    Rectangle {
      x: lens.half - width / 2
      width: Math.max(2, Style.space(2))
      height: lens.height
      color: Color.accent
    }

    Chip { x: Style.spacing.sm; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.spacing.sm; text: "Original" }
    Chip { anchors.right: parent.right; anchors.rightMargin: Style.spacing.sm; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.spacing.sm; text: "Upscayled" }
  }

  HoverHandler {
    id: hover
    onPointChanged: root.pointer = point.position
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.comparing && root.mode === "slider"
    cursorShape: Qt.SizeHorCursor
    onPressed: function(mouse) { root.split = Math.max(0, Math.min(1, mouse.x / root.width)) }
    onPositionChanged: function(mouse) {
      if (pressed) root.split = Math.max(0, Math.min(1, mouse.x / root.width))
    }
  }
}
