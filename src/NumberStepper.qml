import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A number entry with no text input, in place of the SDK NumberField.
//
// An editable Qt TextInput (which NumberField's SpinBox contains) reads the
// clipboard's whole text each time the clipboard changes, paste or not
// (QQuickTextInput::q_canPasteChanged, Qt 6.12). Inside omarchy-shell, any
// other program that owns the clipboard could stall or flood the shell that
// way. This shows the number as plain text and takes the keys itself:
// digits and Backspace to type a value, Enter to set it, Escape to cancel,
// Up/Down and PageUp/PageDown to step, plus the arrow buttons.
Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent

  signal modified(int value)

  property string typed: ""           // digits typed since focus; "" when not typing
  readonly property bool editing: box.activeFocus

  spacing: Style.spacing.md

  function clamp(v) { return Math.max(from, Math.min(to, v)) }
  function current() { return typed !== "" ? clamp(parseInt(typed, 10)) : value }
  function set(v) {
    typed = ""
    v = clamp(v)
    if (v !== value) modified(v)
  }
  function commit() { if (typed !== "") set(parseInt(typed, 10)) }
  function step(n) { set(current() + n * stepSize) }

  // One key press; returns whether it was used. (Separate from Keys.onPressed
  // so tests/stepper.sh can drive it.)
  function key(k) {
    if (k >= Qt.Key_0 && k <= Qt.Key_9) {
      if (typed.length < String(to).length) typed = (typed === "0" ? "" : typed) + (k - Qt.Key_0)
    } else if (k === Qt.Key_Backspace) {
      typed = (typed !== "" ? typed : String(value)).slice(0, -1) || "0"
    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      commit()
    } else if (k === Qt.Key_Escape && typed !== "") {
      typed = ""
    } else if (k === Qt.Key_Up || k === Qt.Key_Down) {
      step(k === Qt.Key_Up ? 1 : -1)
    } else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) {
      step(k === Qt.Key_PageUp ? 10 : -10)
    } else {
      return false
    }
    return true
  }

  Text {
    textFormat: Text.PlainText
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Item {
    id: box
    width: Style.spacing.numberFieldWidth
    height: Math.max(Style.spacing.controlHeight, Style.font.body + Style.spacing.controlPaddingY * 2)
    activeFocusOnTab: true

    readonly property bool hot: hover.hovered
    readonly property var borderSpec: Border.controlSpec(box.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
                                                         root.foreground, root.accent)

    Accessible.role: Accessible.SpinBox
    Accessible.name: root.label
    Accessible.description: String(root.current())

    onActiveFocusChanged: if (!activeFocus) root.commit()

    Keys.onPressed: function(event) { event.accepted = root.key(event.key) }

    BorderSurface {
      anchors.fill: parent
      color: Style.controlFill(box.activeFocus, box.hot, root.foreground, root.accent)
      borderSpec: box.borderSpec
      radius: Style.cornerRadius
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: box.forceActiveFocus() }

    Text {
      id: shown
      textFormat: Text.PlainText
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: -arrows.width / 2
      text: root.typed !== "" ? root.typed : Number(root.value).toLocaleString(Qt.locale(), "f", 0)
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    // A caret while typing, so it is clear the keys go here.
    Rectangle {
      visible: root.typed !== ""
      x: shown.x + shown.width + 1
      anchors.verticalCenter: shown.verticalCenter
      width: Math.max(1, Style.normalBorderWidth)
      height: shown.height
      color: root.accent
    }

    Column {
      id: arrows
      anchors.right: parent.right
      anchors.rightMargin: Border.right(box.borderSpec) + Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        model: [1, -1]
        delegate: Item {
          id: arrow
          required property int modelData
          width: Style.space(14)
          height: box.height / 2 - Style.spacing.xs
          opacity: (modelData > 0 ? root.current() < root.to : root.current() > root.from) ? 1 : 0.35

          Canvas {
            anchors.centerIn: parent
            width: Style.space(7)
            height: Style.space(4)
            property color tint: root.foreground
            onTintChanged: requestPaint()
            onPaint: {
              var c = getContext("2d")
              c.reset()
              c.fillStyle = tint
              c.beginPath()
              if (arrow.modelData > 0) { c.moveTo(0, height); c.lineTo(width / 2, 0); c.lineTo(width, height) }
              else { c.moveTo(0, 0); c.lineTo(width / 2, height); c.lineTo(width, 0) }
              c.closePath()
              c.fill()
            }
          }

          TapHandler {
            onTapped: {
              box.forceActiveFocus()
              root.step(arrow.modelData)
            }
          }
        }
      }
    }
  }
}
