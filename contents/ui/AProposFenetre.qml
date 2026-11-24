/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * SPDX-FileCopyrightText: 2026 naykkalak
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// "About" (2.0): same layout as the one in "This PC", with the series logo.
// A Plasma window, like the menu and the "···" window of the panel: under Wayland, only a
// window of this type is guaranteed to appear in front of the menu, which stays open behind it.
// No "new version" checkbox: the widget is updated through KDE.
PlasmaCore.Dialog {
    id: aPropos

    flags: Qt.WindowStaysOnTopHint
    location: PlasmaCore.Types.Floating
    hideOnWindowDeactivate: false
    visible: false

    function ouvrir() {
        visible = true;
        Qt.callLater(centrer);
        requestActivate();
    }
    function fermer() { visible = false; }
    // centered on the menu's screen
    function centrer() {
        var e = kicker.screenGeometry;
        x = Math.round(e.x + (e.width - width) / 2);
        y = Math.round(e.y + (e.height - height) / 2);
    }

    mainItem: Item {
        width: 480
        height: colonne.implicitHeight + 40 + 16 + 50   // title bar + content + button
        focus: true
        Keys.onEscapePressed: aPropos.fermer()

        // title bar, like the "This PC" and Search windows
        Item {
            id: barreTitre
            width: parent.width
            height: 32
            QQC2.Label {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: i18n("About Fenestra Menu 11")
            }
        }

        QQC2.Button {   // "Close" anchored bottom right, like the other Fenestra windows
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            text: i18n("Close")
            onClicked: aPropos.fermer()
        }

        ColumnLayout {
            id: colonne
            x: 16
            y: 40   // below the title bar
            width: 480 - 32
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Kirigami.Icon {
                    source: Plasmoid.icon || "start-here-kde"
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    QQC2.Label {
                        text: "Fenestra Menu 11"
                        font.pixelSize: 22
                        font.bold: true
                    }
                    QQC2.Label {
                        text: i18n("Version %1", Plasmoid.metaData.version)
                        opacity: 0.75
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {   // the series logo in front of its description
                Layout.fillWidth: true
                spacing: 12
                Image {   // 2.0: like "This PC": drawn at the exact size, sharp edges
                    source: Qt.resolvedUrl("../icons/fenestra-logo.svg")
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    sourceSize.width: 40 * Screen.devicePixelRatio
                    sourceSize.height: 40 * Screen.devicePixelRatio
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: false
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: i18n("Part of the Fenestra series, which gives KDE Plasma the look of a Windows 11 desktop.")
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Author: %1", "naykkalak")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("License: %1", i18n("GPL-3.0 or later"))
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.75
                text: i18n("This software is neither affiliated with nor endorsed by Microsoft Corporation. Windows is a trademark of Microsoft Corporation.")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.75
                text: i18n("Based on Menu 11 Next by Eisteed and on Menu 11 by adhe (GPL-2.0 or later).")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.75
                text: i18n("Mobile panel and power icons: Fluent UI System Icons, © Microsoft Corporation, MIT license.")
            }
        }
    }
}
