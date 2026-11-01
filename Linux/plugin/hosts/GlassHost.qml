import QtQuick
import qs.Commons
import "../../denon.bar/panels" as Kit

// The frosted panel host from the denon.bar plugin (hover to preview, click
// to keep). Only loaded when that plugin is installed; same API as StockHost.
Kit.PopupPanel {
  id: host
  property var softly: null
  readonly property Item slot: slotItem
  function commitHover(owner) { return Kit.PanelMotion.commitHover(owner) }

  owner: softly
  open: softly ? softly.opened : false
  focusTarget: softly ? softly.keyboardItem : null
  contentWidth: host.fittedContentWidth(Style.space(340))
  contentHeight: host.fittedContentHeight(softly ? softly.contentImplicitHeight : 0, Style.space(700))

  Item { id: slotItem; anchors.fill: parent }
}
