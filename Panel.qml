import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "culcat.cursor-finder"
  readonly property var activeService: {
    if (root.service) return root.service
    if (root.shell && typeof root.shell.serviceFor === "function") {
      return root.shell.serviceFor(root.pluginId)
    }
    return null
  }

  function open(_payloadJson) {
    root.opened = true
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide(root.pluginId)
    } else {
      close()
    }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-cursor-finder-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      BorderSurface {
        id: card
        anchors.centerIn: parent
        width: Style.space(420)
        height: contentCol.implicitHeight + Style.space(44)
        color: Util.alpha(Commons.Color.background, 0.98)
        borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        ColumnLayout {
          id: contentCol
          anchors.fill: parent
          anchors.margins: Style.space(22)
          spacing: Style.space(16)

          // Header
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "󰇀  Cursor Finder"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              Layout.fillWidth: true
            }

            Rectangle {
              width: statusLabel.implicitWidth + Style.space(16)
              height: Style.space(26)
              radius: Style.cornerRadius
              color: root.activeService && root.activeService.enabled
                ? Util.alpha(Commons.Color.accent, 0.22)
                : Util.alpha(Commons.Color.foreground, 0.12)
              border.width: 1
              border.color: root.activeService && root.activeService.enabled
                ? Commons.Color.accent
                : Util.alpha(Commons.Color.foreground, 0.25)

              Text {
                id: statusLabel
                anchors.centerIn: parent
                text: root.activeService && root.activeService.enabled ? "Enabled" : "Disabled"
                color: root.activeService && root.activeService.enabled
                  ? Commons.Color.accent
                  : Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.activeService) {
                    root.activeService.applySettingsObject({ enabled: !root.activeService.enabled }, true)
                  }
                }
              }
            }
          }

          Text {
            text: "Shake the mouse pointer rapidly to temporarily enlarge it, just like macOS."
            color: Util.alpha(Commons.Color.foreground, 0.72)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // Sensitivity row
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "SHAKE SENSITIVITY"
              color: Util.alpha(Commons.Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Repeater {
                model: [
                  { label: "Low", value: 0.7 },
                  { label: "Normal", value: 1.0 },
                  { label: "High", value: 1.4 },
                  { label: "Ultra", value: 1.9 }
                ]

                delegate: Rectangle {
                  required property var modelData
                  readonly property bool selected: root.activeService
                    && Math.abs(root.activeService.sensitivity - modelData.value) < 0.15

                  Layout.fillWidth: true
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: selected ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.08)

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.selected ? Commons.Color.background : Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.selected
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.activeService) {
                        root.activeService.applySettingsObject({ sensitivity: modelData.value }, true)
                      }
                    }
                  }
                }
              }
            }
          }

          // Max Scale row
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "ENLARGED CURSOR SIZE"
              color: Util.alpha(Commons.Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Repeater {
                model: [
                  { label: "3× (72px)", value: 3.0 },
                  { label: "4× (96px)", value: 4.2 },
                  { label: "5× (120px)", value: 5.0 },
                  { label: "6× (144px)", value: 6.0 }
                ]

                delegate: Rectangle {
                  required property var modelData
                  readonly property bool selected: root.activeService
                    && Math.abs(root.activeService.maxScale - modelData.value) < 0.35

                  Layout.fillWidth: true
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: selected ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.08)

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.selected ? Commons.Color.background : Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.selected
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.activeService) {
                        root.activeService.applySettingsObject({ maxScale: modelData.value }, true)
                      }
                    }
                  }
                }
              }
            }
          }

          // Cursor Style row
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "CURSOR APPEARANCE"
              color: Util.alpha(Commons.Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Repeater {
                model: [
                  { label: "macOS Classic", value: "macos" },
                  { label: "Theme Accent", value: "theme" },
                  { label: "Inverted White", value: "inverted" }
                ]

                delegate: Rectangle {
                  required property var modelData
                  readonly property bool selected: root.activeService
                    && root.activeService.cursorStyle === modelData.value

                  Layout.fillWidth: true
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: selected ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.08)

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.selected ? Commons.Color.background : Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.selected
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.activeService) {
                        root.activeService.applySettingsObject({ cursorStyle: modelData.value }, true)
                      }
                    }
                  }
                }
              }
            }
          }

          // Halo ring toggle + Test button row
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.activeService && root.activeService.showHalo
                ? Util.alpha(Commons.Color.accent, 0.2)
                : Util.alpha(Commons.Color.foreground, 0.08)
              border.width: 1
              border.color: root.activeService && root.activeService.showHalo
                ? Commons.Color.accent
                : "transparent"

              Text {
                anchors.centerIn: parent
                text: root.activeService && root.activeService.showHalo ? "adjust  Halo Ring: ON" : "Halo Ring: OFF"
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.activeService) {
                    root.activeService.applySettingsObject({ showHalo: !root.activeService.showHalo }, true)
                  }
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: Commons.Color.accent

              Text {
                anchors.centerIn: parent
                text: "Test Locate Pulse"
                color: Commons.Color.background
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.activeService) {
                    root.activeService.locate()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
