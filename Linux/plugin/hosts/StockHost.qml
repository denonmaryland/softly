import QtQuick
import qs.Ui
import qs.Commons

// Omarchy's stock popup card. Softly reparents its content into `slot`.
KeyboardPanel {
  id: host
  property var softly: null
  readonly property Item slot: slotItem
  function commitHover(owner) { return false }

  owner: softly
  open: softly ? softly.opened : false
  focusTarget: softly ? softly.keyboardItem : null
  padding: Style.space(12)
  contentWidth: host.fittedContentWidth(Style.space(340))
  contentHeight: host.fittedContentHeight(softly ? softly.contentImplicitHeight : 0, Style.space(700))

  Item { id: slotItem; anchors.fill: parent }
}
