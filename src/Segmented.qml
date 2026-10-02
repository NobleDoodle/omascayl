import QtQuick
import qs.Commons
import qs.Ui

// Equal-width segmented control built from the Omarchy Button, for the tab
// bar and the small option rows (ButtonGroup sizes its chips to their text).
Row {
  id: root

  property var options: []          // [{ value, label }]
  property string value: ""
  property bool enabled: true

  signal changed(string value)

  spacing: Style.spacing.sm

  Repeater {
    model: root.options

    delegate: Button {
      required property var modelData
      width: (root.width - root.spacing * (root.options.length - 1)) / root.options.length
      text: modelData.label
      selected: modelData.value === root.value
      bordered: true
      enabled: root.enabled
      opacity: root.enabled ? 1 : 0.5
      onClicked: if (root.enabled && modelData.value !== root.value) root.changed(modelData.value)
    }
  }
}
