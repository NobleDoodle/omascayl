import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Omarchy's PanelSlider with window colors instead of bar colors.
PanelSlider {
  trackColor: Style.selectedFill
  fillColor: enabled ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.4)
  knobColor: Commons.Color.foreground
}
