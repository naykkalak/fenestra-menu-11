/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Modified by naykkalak (2026) for Fenestra Menu 11, a fork of Menu 11 Next by Eisteed.
 * The original notice below is kept. This file is GPL-2.0-or-later;
 * Fenestra Menu 11 as a whole is distributed under GPL-3.0-or-later.
 */
/*
SPDX-FileCopyrightText: 2015 Eike Hein <hein@kde.org>

SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.ksvg 1.0 as KSvg
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.private.kicker 0.1 as Kicker
import org.kde.plasma.plasmoid

PlasmaComponents.ScrollView {
    id: itemMultiGrid

    PlasmaComponents.ScrollBar.vertical: PlasmaComponents.ScrollBar {   // Fenestra : barre façon Windows 11
        id: barreFenestra
        parent: itemMultiGrid   // Fenestra : placement dans la ScrollView
        x: itemMultiGrid.mirrored ? 0 : itemMultiGrid.width - width
        y: itemMultiGrid.topPadding
        height: itemMultiGrid.availableHeight
        implicitWidth: 14   // largeur d'origine de la barre du thème
        hoverEnabled: true
        visible: size < 1.0 && policy !== PlasmaComponents.ScrollBar.AlwaysOff
        readonly property bool survol: hovered || pressed
        readonly property bool eveille: active || extinction.running
        function reveil() { extinction.restart(); }   // appelée quand la souris bouge
        Timer { id: extinction; interval: 1500 }
        background: KSvg.FrameSvgItem {   // survol : fond du thème
            imagePath: "widgets/scrollbar"
            prefix: "background-vertical"
            transform: Translate { x: 4 }   // Fenestra : collé au bord, comme Windows
            opacity: barreFenestra.survol ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        contentItem: Item {
            implicitWidth: 14
            Rectangle {   // souris qui bouge : trait fin côté bord
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 3
                anchors.bottomMargin: 3
                width: 2
                radius: 1
                color: Kirigami.Theme.textColor
                opacity: (barreFenestra.eveille && !barreFenestra.survol) ? 0.55 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
            KSvg.FrameSvgItem {   // survol / glissement : poignée du thème
                anchors.fill: parent
                imagePath: "widgets/scrollbar"
                prefix: "mouseover-slider"
                transform: Translate { x: 4 }   // Fenestra : collé au bord, comme Windows
                opacity: barreFenestra.survol ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    width: parent.width

    implicitHeight: itemColumn.implicitHeight

    signal keyNavUp
    signal keyNavDown

    property bool grabFocus: false

    property alias model: repeater.model
    property alias count: repeater.count

    // Fenestra : real number of results (count is the number of sections, even empty ones)
    property int nbResultats: 0
    property Component pied: null   // Fenestra : optional last line under the results (web search)
    function recompter() {
        var n = 0;
        for (var i = 0; i < repeater.count; i++) {
            var it = repeater.itemAt(i);
            if (it && it.itemGrid) n += it.itemGrid.count;
        }
        nbResultats = n;
    }
    property alias flickableItem: flickable

    property int itemColumns
    property int cellWidth
    property int cellHeight

    function subGridAt(index) {
        return repeater.itemAt(index).itemGrid;
    }

    function tryActivate(row, col) {
        if (flickable.contentY > 0) {
            row = 0;
        }

        var target = null;
        var rows = 0;

        for (var i = 0; i < repeater.count; i++) {
            var grid = subGridAt(i);
            if (grid.count > 0) {
                if (rows <= row) {
                    target = grid;
                    rows += grid.lastRow() + 2;
                } else {
                    break;
                }
            }
        }

        if (target) {
            rows -= (target.lastRow() + 2);
            target.tryActivate(row - rows, col);
        }
    }

    onFocusChanged: {
        if (!focus) {
            for (var i = 0; i < repeater.count; i++) {
                subGridAt(i).focus = false;
            }
        }
    }

    Flickable {
        id: flickable

        width: itemMultiGrid.availableWidth
        height: itemMultiGrid.availableHeight
        clip: true

        flickableDirection: Flickable.VerticalFlick
        contentHeight: itemColumn.implicitHeight
        contentWidth: width
        HoverHandler { onPointChanged: barreFenestra.reveil() }   // Fenestra : réveil de la barre

        Column {
            id: itemColumn

            width: flickable.width - (barreFenestra.visible ? 0 : barreFenestra.implicitWidth)   // 2.0 : même marge à droite avec ou sans barre

            Repeater {
                id: repeater
                onCountChanged: Qt.callLater(itemMultiGrid.recompter)   // Fenestra

                delegate: Item {
                    id: itemTest
                    width: itemColumn.width
                    height: visible ? sectionLayout.implicitHeight : 0
                    visible: gridView.count > 0

                    property Item itemGrid: gridView
                    property bool sectionCollapsed: false
                    readonly property int nbSection: gridView.count   // Fenestra : results of this section
                    onNbSectionChanged: Qt.callLater(itemMultiGrid.recompter)
                    Component.onDestruction: Qt.callLater(itemMultiGrid.recompter)

                    Column {
                        id: sectionLayout
                        width: parent.width
                        spacing: 0

                        // Windows 11-style category section header
                        Item {
                            id: sectionHeader
                            width: parent.width
                            height: categoryLabel.implicitHeight + Kirigami.Units.smallSpacing * 3

                            // Left accent line
                            Rectangle {
                                id: accentBar
                                anchors.left: parent.left
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                anchors.verticalCenter: categoryLabel.verticalCenter
                                width: 3
                                height: categoryLabel.implicitHeight * 0.85
                                radius: 2
                                color: Kirigami.Theme.highlightColor
                                opacity: 0.85
                            }

                            // Category icon
                            Kirigami.Icon {
                                id: categoryIcon
                                anchors.left: accentBar.right
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.verticalCenter: categoryLabel.verticalCenter
                                width: Kirigami.Units.iconSizes.smallMedium
                                height: width
                                source: {
                                    if (!repeater.model) return ""
                                    var idx = repeater.model.index(index, 0)
                                    var icon = repeater.model.data(idx, Qt.DecorationRole)
                                    return icon || ""
                                }
                                visible: source !== ""
                            }

                            // Category name
                            Text {
                                id: categoryLabel
                                anchors.left: categoryIcon.visible ? categoryIcon.right : accentBar.right
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.top: parent.top
                                anchors.topMargin: Kirigami.Units.smallSpacing
                                anchors.right: collapseChevron.left
                                anchors.rightMargin: Kirigami.Units.smallSpacing

                                text: {
                                    if (!repeater.model) return ""
                                    var idx = repeater.model.index(index, 0)
                                    var name = repeater.model.data(idx, Qt.DisplayRole)
                                    return name || repeater.model.modelForRow(index).description || ""
                                }
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                                font.weight: Font.DemiBold
                                color: Kirigami.Theme.textColor
                                opacity: 0.75
                                elide: Text.ElideRight
                            }

                            // Collapse/expand chevron
                            Kirigami.Icon {
                                id: collapseChevron
                                anchors.right: parent.right
                                anchors.rightMargin: Kirigami.Units.smallSpacing   // 2.0 : flèche en face de la roue dentée
                                anchors.verticalCenter: categoryLabel.verticalCenter
                                width: Kirigami.Units.iconSizes.small
                                height: width
                                source: itemTest.sectionCollapsed ? "arrow-right" : "arrow-down"
                                opacity: headerHover.containsMouse ? 0.9 : 0.45

                                Behavior on opacity { NumberAnimation { duration: 100 } }
                            }

                            // Subtle bottom separator line
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Kirigami.Theme.textColor
                                opacity: 0.08
                            }

                            MouseArea {
                                id: headerHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: itemTest.sectionCollapsed = !itemTest.sectionCollapsed
                            }
                        }

                        // Spacing between header and grid
                        Item {
                            width: parent.width
                            height: Kirigami.Units.smallSpacing
                            visible: !itemTest.sectionCollapsed
                        }

                        ItemGridView {
                            id: gridView
                            visible: !itemTest.sectionCollapsed
                            molettePropre: false   // Fenestra : the native scrolling of this view handles the wheel
                            surlignageSearch: true   // Fenestra : surlignement de Fenestra Search

                            Connections {
                                target: gridView

                                function onKeyNavDown() {
                                    if (gridView.currentIndex < gridView.count - 1) {
                                        gridView.currentIndex += 1
                                        return
                                    }

                                    var i = index
                                    for (var j = i + 1; j < repeater.count; j++) {
                                        var nextDelegate = repeater.itemAt(j)
                                        var next = nextDelegate.itemGrid
                                        if (next.count > 0 && !nextDelegate.sectionCollapsed) {
                                            next.currentIndex = 0
                                            next.focus = true
                                            return
                                        }
                                    }
                                }

                                function onKeyNavUp() {
                                    if (gridView.currentIndex > 0) {
                                        gridView.currentIndex -= 1
                                        return
                                    }

                                    var i = index
                                    for (var j = i - 1; j >= 0; j--) {
                                        var prevDelegate = repeater.itemAt(j)
                                        var prev = prevDelegate.itemGrid
                                        if (prev.count > 0 && !prevDelegate.sectionCollapsed) {
                                            prev.currentIndex = prev.count - 1
                                            prev.focus = true
                                            return
                                        }
                                    }

                                    if (i === 0 && gridView.currentIndex === 0) {
                                        searchField.forceActiveFocus()
                                    }
                                }
                            }

                            width: parent.width
                            height: {
                                var cols = Math.max(1, Math.floor(width / itemMultiGrid.cellWidth))
                                return Math.ceil(count / cols) * itemMultiGrid.cellHeight
                            }
                            itemColumns: 2

                            cellWidth: itemMultiGrid.cellWidth
                            cellHeight: itemMultiGrid.cellHeight
                            iconSize: 22   // Fenestra : icônes de Fenestra Search

                            verticalScrollBarPolicy: PlasmaComponents.ScrollBar.AlwaysOff
                            bypassArrowNav: true
                            model: repeater.model.modelForRow(index)

                            onFocusChanged: {
                                if (focus) {
                                    itemMultiGrid.focus = true;
                                }
                            }

                            onCountChanged: {
                                if (itemMultiGrid.grabFocus && index == 0 && count > 0) {
                                    currentIndex = 0;
                                    focus = true;
                                }
                            }

                            onCurrentItemChanged: {
                                if (!currentItem) {
                                    return;
                                }

                                if (index == 0 && currentRow() === 0) {
                                    flickable.contentY = 0;
                                    return;
                                }

                                // 2.0 : le survol à la souris ne fait pas défiler la liste : seulement la navigation au clavier
                                if (typeof rootItem !== "undefined" && !rootItem.keyNavRecently()) {
                                    return;
                                }

                                var y = currentItem.y;
                                y = contentItem.mapToItem(flickable.contentItem, 0, y).y;

                                if (y < flickable.contentY) {
                                    flickable.contentY = y;
                                } else {
                                    y += itemMultiGrid.cellHeight;
                                    y -= flickable.contentY;
                                    y -= itemMultiGrid.height;

                                    if (y > 0) {
                                        flickable.contentY += y;
                                    }
                                }
                            }
                        }

                        // Bottom gap between sections
                        Item {
                            width: parent.width
                            height: itemTest.sectionCollapsed
                                    ? Kirigami.Units.smallSpacing
                                    : Kirigami.Units.largeSpacing * 2
                        }
                    }
                }
            }

            // Fenestra : last line under the results
            Loader {
                width: itemColumn.width
                active: itemMultiGrid.pied !== null
                sourceComponent: itemMultiGrid.pied
            }
        }

        Kicker.WheelInterceptor {
            width: flickable.width
            height: flickable.height
            y: flickable.contentY   // Fenestra : reste sur la partie visible de la liste
            z: 1
            destination: flickable   // Fenestra : la molette fait défiler la liste
        }
    }
}
