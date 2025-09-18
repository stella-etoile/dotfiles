import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: aboutTab

    property bool isHyprland: CompositorService.isHyprland

    DankFlickable {
        anchors.fill: parent
        anchors.topMargin: Theme.spacingL
        clip: true
        contentHeight: mainColumn.height
        contentWidth: width

        Column {
            id: mainColumn

            width: parent.width
            spacing: Theme.spacingXL

            // Technical Details
            StyledRect {
                width: parent.width
                height: techSection.implicitHeight + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g,
                               Theme.surfaceVariant.b, 0.3)
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g,
                                      Theme.outline.b, 0.2)
                border.width: 1

                Column {
                    id: techSection

                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "code"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Technical Details"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: Theme.spacingL
                        rowSpacing: Theme.spacingS

                        StyledText {
                            text: "Framework:"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: `<a href="https://quickshell.org" style="text-decoration:none; color:${Theme.primary};">Quickshell</a>`
                            linkColor: Theme.primary
                            textFormat: Text.RichText
                            onLinkActivated: url => Qt.openUrlExternally(url)
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                acceptedButtons: Qt.NoButton
                                propagateComposedEvents: true
                            }
                        }

                        StyledText {
                            text: "Language:"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: "QML (Qt Modeling Language)"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: "Compositor:"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Row {
                            spacing: 4
                            
                            StyledText {
                                text: `<a href="https://gcan you do ascii textithub.com/YaLTeR/niri" style="text-decoration:none; color:${Theme.primary};">niri</a>`
                                font.pixelSize: Theme.fontSizeMedium
                                linkColor: Theme.primary
                                textFormat: Text.RichText
                                color: Theme.surfaceVariantText
                                onLinkActivated: url => Qt.openUrlExternally(url)
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    acceptedButtons: Qt.NoButton
                                    propagateComposedEvents: true
                                }
                            }
                        }

                        StyledText {
                            text: "System Monitoring:"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Row {
                            spacing: 4
                            
                            StyledText {
                                text: `<a href="https://github.com/AvengeMedia/dgop" style="text-decoration:none; color:${Theme.primary};">dgop</a>`
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                linkColor: Theme.primary
                                textFormat: Text.RichText
                                onLinkActivated: url => Qt.openUrlExternally(url)
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    acceptedButtons: Qt.NoButton
                                    propagateComposedEvents: true
                                }
                            }
                            
                            StyledText {
                                text: "- Stateless System Monitoring"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

        }
    }

    // Community tooltip - positioned absolutely above everything
    Rectangle {
        id: communityTooltip
        parent: aboutTab
        z: 1000

        property var hoveredButton: {
            if (compositorButton.hovered) return compositorButton
            if (matrixButton.visible && matrixButton.hovered) return matrixButton
            if (discordButton.hovered) return discordButton
            if (redditButton.hovered) return redditButton
            return null
        }

        property string tooltipText: hoveredButton ? hoveredButton.tooltipText : ""

        visible: hoveredButton !== null && tooltipText !== ""
        width: tooltipLabel.implicitWidth + 24
        height: tooltipLabel.implicitHeight + 12

        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.width: 1
        border.color: Theme.outlineMedium

        x: hoveredButton ? hoveredButton.mapToItem(aboutTab, hoveredButton.width / 2, 0).x - width / 2 : 0
        y: hoveredButton ? communityIcons.mapToItem(aboutTab, 0, 0).y - height - 8 : 0

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowOpacity: 0.15
            shadowVerticalOffset: 2
            shadowBlur: 0.5
        }

        StyledText {
            id: tooltipLabel
            anchors.centerIn: parent
            text: communityTooltip.tooltipText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
        }
    }
}
