import QtQuick
import qs.Commons
import qs.Ui

// Omarchy's PanelSlider with window colors instead of bar colors.
PanelSlider {
  trackColor: Style.selectedFill
  fillColor: enabled ? Color.accent : Util.alpha(Color.foreground, 0.4)
  knobColor: Color.foreground
}
