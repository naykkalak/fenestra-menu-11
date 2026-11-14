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

// « À propos » (2.0) : même présentation que celle de Ce PC, avec le logo de la série.
// Fenêtre Plasma, comme le menu et la fenêtre « ··· » du volet : sous Wayland, seule une
// fenêtre de ce type passe à coup sûr devant le menu, qui reste ouvert derrière.
// Pas de case « nouvelle version » : le widget se met à jour par KDE.
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
    // centrée sur l'écran du menu
    function centrer() {
        var e = kicker.screenGeometry;
        x = Math.round(e.x + (e.width - width) / 2);
        y = Math.round(e.y + (e.height - height) / 2);
    }

    mainItem: Item {
        width: 480
        height: colonne.implicitHeight + 40 + 16 + 50   // barre de titre + contenu + bouton
        focus: true
        Keys.onEscapePressed: aPropos.fermer()

        // barre de titre, comme les fenêtres de Ce PC et de Search
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

        QQC2.Button {   // « Fermer » ancré en bas à droite, comme les autres fenêtres Fenestra
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            text: i18n("Close")
            onClicked: aPropos.fermer()
        }

        ColumnLayout {
            id: colonne
            x: 16
            y: 40   // sous la barre de titre
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

            RowLayout {   // le logo de la série devant sa présentation
                Layout.fillWidth: true
                spacing: 12
                Image {   // 2.0 : comme « Ce PC » : dessiné à la taille exacte, bords nets
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
