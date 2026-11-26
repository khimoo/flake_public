import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popupWin

    required property var store

    visible: store.activePopups.length > 0
    color: "transparent"

    anchors {
        top: true
        right: true
    }

    margins {
        top: 12
        right: 12
    }

    implicitWidth: 320
    implicitHeight: Math.max(1, popupColumn.implicitHeight)

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-hub-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ColumnLayout {
        id: popupColumn
        width: parent.width
        spacing: 6

        Repeater {
            model: store.activePopups

            Rectangle {
                id: card
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: contentRow.implicitHeight + 16
                radius: Theme.radiusMedium
                color: Theme.base
                border.width: 1
                border.color: modelData.isCritical ? Theme.red : Theme.surface1

                // 左端の控えめな緊急度アクセントバー
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    width: 3
                    radius: 2
                    color: modelData.isCritical ? Theme.red : Theme.accent
                }

                RowLayout {
                    id: contentRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: card.modelData.appName
                                color: card.modelData.isCritical ? Theme.red : Theme.subtext
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: card.modelData.timeText
                                color: Theme.muted
                                font.family: Theme.monoFamily
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            visible: text.length > 0
                            text: card.modelData.summary
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: text.length > 0
                            text: card.modelData.body
                            color: Theme.subtext
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            Layout.fillWidth: true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            store.dismissPopup(card.modelData.entryId);
                        } else {
                            store.invokeDefault(card.modelData);
                        }
                    }
                }
            }
        }
    }
}
