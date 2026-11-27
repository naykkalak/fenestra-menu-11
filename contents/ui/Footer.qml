/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtCore
import Qt5Compat.GraphicalEffects

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

import org.kde.plasma.private.kicker 0.1 as Kicker
import org.kde.coreaddons 1.0 as KCoreAddons
import org.kde.plasma.private.shell

import org.kde.kwindowsystem
import org.kde.kquickcontrolsaddons

import org.kde.plasma.components as PlasmaComponents3


import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions

RowLayout{

    Logic { id: monLogic }

    spacing: Kirigami.Units.largeSpacing

    signal tabOut

    // closes the footer's windows (Account, other accounts, Power);
    // called by MenuRepresentation.qml when the menu closes
    function closeMenus() {
        usersMenu.visible = false;
        accountMenu.visible = false;
        powerMenu.visible = false;
    }

    Keys.onTabPressed: event => {
        event.accepted = true;
        tabOut();
    }

    KCoreAddons.KUser {   id: kuser  }
    //Logic {   id: logic }

    SessionManagement {
        id: sessionManager
    }

    // ── Shell command launcher (e.g. open System Settings)
    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: (sourceName, data) => disconnectSource(sourceName)
        function run(cmd) { connectSource(cmd) }
    }

    // ── List of the other local accounts (uid >= 1000, excluding the current user
    // and accounts without a login shell) - re-read each time the
    // "Other users" popup opens, via refresh()
    Plasma5Support.DataSource {
        id: usersCheck
        engine: "executable"
        connectedSources: []
        property var users: []
        Component.onCompleted: refresh()
        readonly property string cmd: "getent passwd | awk -F: -v OFS='|' '$3>=1000 && $3<60000 && $7!~/nologin|false/ {print $1,$5}'"

        // Each refresh uses a slightly different source (a timestamped
        // shell comment, ignored at execution) to stop the "executable"
        // engine from serving the old cached answer again.
        property string currentSource: ""

        function refresh() {
            if (currentSource !== "") {
                disconnectSource(currentSource);
            }
            currentSource = cmd + " #" + Date.now();
            connectSource(currentSource);
        }

        onNewData: (sourceName, data) => {
            var out = ((data["stdout"] || "") + "").trim();
            var list = [];
            if (out !== "") {
                var lines = out.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("|");
                    var login = parts[0];
                    if (login === "" || login === kuser.loginName) {
                        continue;
                    }
                    var full = (parts[1] || "").split(",")[0].trim();
                    list.push({ login: login, name: full !== "" ? full : login });
                }
            }
            users = list;
        }
    }

    // ── "Account" button - avatar + name. Opens the Account window
    // (distribution logo, avatar, name, account type, links).
    //
    // To keep the main menu from closing when this window
    // takes focus, the two signals below must be connected
    // in MenuRepresentation.qml:
    //   onAccountMenuAboutToOpen: root.hideOnWindowDeactivate = false
    //   onAccountMenuClosed:      root.hideOnWindowDeactivate = true
    signal accountMenuAboutToOpen
    signal accountMenuClosed

    Item {
        id: accountButton
        // account-frame-v1: same style as the Power button
        implicitWidth: userInfoRow.implicitWidth + 20
        implicitHeight: userInfoRow.implicitHeight + 8
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 15 // account-frame-v2: 25 - 10 (the frame overflows, the avatar stays in place)

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (accountMouse.containsMouse || accountMouse.pressed || accountMenu.visible) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        RowLayout {
            id: userInfoRow
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter

            Item {
                id: avatarMaskContainer
                width: 36
                height: 36
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: iconUser
                    anchors.fill: parent
                    source: {
                        var faceUrl = kuser.faceIconUrl.toString()
                        if (faceUrl !== "") {
                            return faceUrl
                        }
                        return Qt.resolvedUrl("../icons/status/fenestra-avatar.svg")   // Fenestra 1.1: default avatar
                    }
                    cache: false
                    visible: false
                    sourceSize.width: 36
                    sourceSize.height: 36
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                }

                Rectangle {
                    id: avatarRoundMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }

                OpacityMask {
                    anchors.fill: parent
                    source: iconUser
                    maskSource: avatarRoundMask
                    visible: iconUser.source !== ""
                }
            }

            Text {
                Layout.leftMargin: 5   // Fenestra: name set apart from the avatar
                wrapMode: Text.NoWrap
                color: Kirigami.Theme.textColor
                font: Kirigami.Theme.defaultFont
                text: qsTr(kuser.fullName)
            }
        }

        MouseArea {
            id: accountMouse
            hoverEnabled: true
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                usersCheck.refresh();
                accountMenuAboutToOpen();
                accountMenu.visible = true;
            }
        }

        PlasmaCore.Dialog {
            id: accountMenu
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true

            onVisibleChanged: {
                if (visible) {
                    Qt.callLater(accountMenu.reposition);
                } else {
                    usersMenu.visible = false;
                    accountMenuClosed();
                }
            }

            function reposition() {
                // Centered horizontally on the button, opens UPWARDS:
                // the Account button is in the same bottom bar as the
                // Power button, at the very bottom of the screen, so there is
                // room only upwards (as for the Power menu).
                var pos = accountButton.mapToGlobal(accountButton.width / 2, 0);
                x = Math.round(pos.x - width / 2);
                y = Math.round(pos.y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                width: 340
                spacing: Kirigami.Units.largeSpacing

                // ── Top row: distro logo on the left, "Sign out" on the right
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                    Layout.topMargin: Kirigami.Units.smallSpacing + 1

                    Image {
                        id: distroLogo
                        property bool primaryFailed: false
                        // Fenestra 1.1: no distribution logo is loaded (element kept empty)
                        source: Qt.resolvedUrl("../icons/fenestra-logo.svg")   // 2.0: Fenestra logo
                        visible: true
                        onStatusChanged: {
                            if (status === Image.Error && !primaryFailed) {
                                primaryFailed = true;
                            }
                        }
                        fillMode: Image.PreserveAspectFit
                        Layout.preferredHeight: 20
                        Layout.preferredWidth: 20
                        Layout.alignment: Qt.AlignVCenter
                        sourceSize.width: 20 * Screen.devicePixelRatio
                        sourceSize.height: 20 * Screen.devicePixelRatio   // 2.0: sharp edges, like "This PC"
                    }

                    Text {   // 2.0: theme name, next to the logo
                        text: "Fenestra theme"
                        color: Kirigami.Theme.textColor
                        opacity: 0.8
                        font.family: Kirigami.Theme.defaultFont.family
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: logoutButton
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: logoutLabel.implicitWidth + 20
                        implicitHeight: logoutLabel.implicitHeight + 12
                        radius: Kirigami.Units.smallSpacing
                        // 2.1: same highlight as the "Shut down" row of the Power menu
                        color: logoutMouse.containsMouse ? (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") : "#00ffffff"
                        border.width: 1
                        border.color: logoutMouse.containsMouse ? (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000") : (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#00ffffff" : "#00000000")
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        Text {
                            id: logoutLabel
                            anchors.centerIn: parent
                            text: i18n("Sign out")
                            color: Kirigami.Theme.textColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                        }

                        MouseArea {
                            id: logoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                accountMenu.visible = false;
                                sessionManager.requestLogout();
                            }
                        }
                    }

                    // ── "..." button (three small dots) - action: lock the session
                    Rectangle {
                        id: moreButton
                        Layout.alignment: Qt.AlignVCenter
                        visible: usersCheck.users.length > 0
                        implicitWidth: 32
                        implicitHeight: logoutButton.implicitHeight
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, (moreMouse.containsMouse || usersMenu.visible) ? 0.07 : 0.0) : Qt.rgba(0, 0, 0, (moreMouse.containsMouse || usersMenu.visible) ? 0.07 : 0.0))
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 3

                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: Kirigami.Theme.textColor
                                }
                            }
                        }

                        MouseArea {
                            id: moreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (usersMenu.visible) {
                                    usersMenu.visible = false;
                                    return;
                                }
                                usersCheck.refresh();
                                // Keeps the Account window from closing when
                                // the popup takes focus
                                accountMenu.hideOnWindowDeactivate = false;
                                usersMenu.visible = true;
                            }
                        }

                        // ── "Other users" popup - small separate
                        // system window, placed BELOW the "..." button
                        PlasmaCore.Dialog {
                            id: usersMenu
                            flags: Qt.WindowStaysOnTopHint
                            location: PlasmaCore.Types.Floating
                            hideOnWindowDeactivate: true

                            onVisibleChanged: {
                                if (visible) {
                                    Qt.callLater(usersMenu.reposition);
                                } else {
                                    accountMenu.hideOnWindowDeactivate = true;
                                    if (accountMenu.visible) {
                                        accountMenu.requestActivate();
                                    }
                                }
                            }

                            function reposition() {
                                // Left edge aligned with the "..." button,
                                // right below it
                                var pos = moreButton.mapToGlobal(0, moreButton.height);
                                x = Math.round(pos.x);
                                y = Math.round(pos.y + Kirigami.Units.smallSpacing);
                            }

                            mainItem: ColumnLayout {
                                width: 260
                                spacing: 0

                                Text {
                                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.topMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                    text: i18n("Other users")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.family: Kirigami.Theme.defaultFont.family
                                    font.pointSize: (Kirigami.Theme.defaultFont.pointSize || 10) - 1
                                }

                                Repeater {
                                    model: usersCheck.users

                                    delegate: PlasmaComponents3.ItemDelegate {
                                        id: userDelegate
                                        Layout.fillWidth: true
                                        hoverEnabled: true
                                        leftPadding: Kirigami.Units.smallSpacing + 6
                                        rightPadding: Kirigami.Units.smallSpacing + 6
                                        topPadding: Kirigami.Units.smallSpacing
                                        bottomPadding: Kirigami.Units.smallSpacing

                                        background: Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            radius: Kirigami.Units.smallSpacing
                                            color: Kirigami.Theme.highlightColor
                                            opacity: userDelegate.hovered ? 0.18 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 100 } }
                                        }

                                        contentItem: RowLayout {
                                            spacing: Kirigami.Units.largeSpacing

                                            Item {
                                                Layout.preferredWidth: 32
                                                Layout.preferredHeight: 32
                                                Layout.alignment: Qt.AlignVCenter

                                                Image {
                                                    id: otherFace
                                                    property bool failed: false
                                                    anchors.fill: parent
                                                    source: failed
                                                        ? Qt.resolvedUrl("../icons/status/fenestra-avatar.svg")   // Fenestra 1.1: default avatar
                                                        : ("file:///var/lib/AccountsService/icons/" + modelData.login)
                                                    onStatusChanged: {
                                                        if (status === Image.Error && !failed) {
                                                            failed = true;
                                                        }
                                                    }
                                                    visible: false
                                                    sourceSize.width: 32
                                                    sourceSize.height: 32
                                                    fillMode: Image.PreserveAspectCrop
                                                    layer.enabled: true
                                                }

                                                Rectangle {
                                                    id: otherFaceMask
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    visible: false
                                                }

                                                OpacityMask {
                                                    anchors.fill: parent
                                                    source: otherFace
                                                    maskSource: otherFaceMask
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                color: Kirigami.Theme.textColor
                                                font.family: Kirigami.Theme.defaultFont.family
                                                font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                                            }
                                        }

                                        onClicked: {
                                            accountMenu.visible = false;
                                            usersMenu.visible = false;
                                            // Opens the user switcher
                                            // (login screen)
                                            if (typeof sessionManager.switchUser === "function") {
                                                sessionManager.switchUser();
                                            } else {
                                                sessionManager.lock();
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: usersCheck.users.length === 0
                                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing + 6
                                    text: i18n("No other users")
                                    color: Kirigami.Theme.textColor
                                    font.family: Kirigami.Theme.defaultFont.family
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                                }
                            }
                        }
                    }
                }

                // ── Avatar + name + account type + link
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                    Layout.bottomMargin: Kirigami.Units.smallSpacing + 6
                    spacing: Kirigami.Units.largeSpacing

                    Item {
                        id: accountAvatarMaskContainer
                        width: 64
                        height: 64
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            id: accountAvatarImg
                            anchors.fill: parent
                            source: iconUser.source
                            cache: false
                            visible: false
                            sourceSize.width: 64
                            sourceSize.height: 64
                            fillMode: Image.PreserveAspectCrop
                            layer.enabled: true
                        }

                        Rectangle {
                            id: accountAvatarRoundMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: accountAvatarImg
                            maskSource: accountAvatarRoundMask
                            visible: accountAvatarImg.source !== ""
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            text: qsTr(kuser.fullName)
                            color: Kirigami.Theme.textColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.weight: Font.DemiBold
                            font.pointSize: (Kirigami.Theme.defaultFont.pointSize || 10) + 3
                        }

                        Text {
                            text: i18n("Local account")
                            color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? "#5D595F" : Kirigami.Theme.disabledTextColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                        }

                        Text {
                            id: manageLink
                            text: i18n("Manage my account")
                            // Fenestra blue in light theme, Plasma link colour in dark theme
                            color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? "#0055A4" : Kirigami.Theme.linkColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                            font.underline: manageMouse.containsMouse

                            MouseArea {
                                id: manageMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    accountMenu.visible = false;
                                    runner.run("kcmshell6 kcm_users");
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    Item{
        Layout.fillWidth: true
    }

    // ── Single "Power" button - opens a separate system window
    // (PlasmaCore.Dialog), not an embedded Popup, so that it can stay
    // perfectly centered on the button even if it exceeds the limits
    // of the main menu window (which cannot display
    // content outside its own edges).
    //
    // To keep the main menu from closing when this second
    // window takes focus (hideOnWindowDeactivate cascading), the two
    // signals below must be connected in MenuRepresentation.qml:
    //   onPowerMenuAboutToOpen: root.hideOnWindowDeactivate = false
    //   onPowerMenuClosed:      root.hideOnWindowDeactivate = true
    signal powerMenuAboutToOpen
    signal powerMenuClosed

    PlasmaComponents3.ToolButton {
        id: powerButton
        icon.width: 22
        icon.height: 22
        icon.source: Qt.resolvedUrl("../icons/status/system-shutdown-v2.svg")   // Fenestra: widget power icon
        Layout.rightMargin: 27 // 20 + 5 + 2 extra points
        // power-frame-v1: square the height of the user block,
        // same style as the taskbar's app buttons
        Layout.preferredWidth: accountButton.implicitHeight - 3   // Fenestra: reduced Power frame
        Layout.preferredHeight: accountButton.implicitHeight - 3
        Layout.alignment: Qt.AlignVCenter
        background: Rectangle {
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (powerButton.hovered || powerButton.down || powerMenu.visible) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        // power-press-v1: the icon sinks on click (like the Start button)
        contentItem: Item {
            implicitWidth: powerButton.icon.width
            implicitHeight: powerButton.icon.height
            Kirigami.Icon {
                anchors.centerIn: parent
                width: powerButton.icon.width
                height: powerButton.icon.height
                source: powerButton.icon.source
                active: false
                isMask: true   // theme text color
                color: Kirigami.Theme.textColor
                scale: powerButton.down ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
            }
        }
        PlasmaComponents3.ToolTip.delay: 400   // 2.0: like the other tooltips (stays as long as the mouse is on the button)
        PlasmaComponents3.ToolTip.visible: hovered && !powerMenu.visible
        PlasmaComponents3.ToolTip.text: i18n("Power")
        visible: sessionManager.canLock || sessionManager.canSuspend || sessionManager.canHibernate === true || sessionManager.canReboot || sessionManager.canShutdown

        onClicked: {
            powerMenuAboutToOpen();
            powerMenu.visible = true;
        }

        // power-recreated (2.0): "powerMenu" becomes a simple switch; the window is recreated on every opening
        QtObject {
            id: powerMenu
            property bool visible: false
            onVisibleChanged: if (!visible) powerMenuClosed()
        }
        Loader {
            active: powerMenu.visible
            sourceComponent: Component {
        PlasmaCore.Dialog {
            id: powerDlg
            visible: true
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true

            onVisibleChanged: {
                if (visible) {
                    Qt.callLater(powerDlg.reposition);
                } else {
                    powerMenu.visible = false;
                }
            }

            function reposition() {
                // Centered horizontally on the button, opens upwards.
                // Separate system window: it can freely overflow the
                // main menu's frame if it grows wider, without ever
                // being truncated.
                var pos = powerButton.mapToGlobal(powerButton.width / 2, 0);
                x = Math.round(pos.x - width / 2);
                y = Math.round(pos.y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                spacing: 0

                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canLock && Plasmoid.configuration.showLockButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-lock-screen-v2.svg")   // Fenestra: widget power icon
                    contentItem: RowLayout {   // icon in the theme's text color
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-lock-screen-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Lock")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // power-highlight-v1
                        border.width: 1                 // same border as the other highlights
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.lock();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canSuspend && Plasmoid.configuration.showSleepButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-suspend-v2.svg")   // Fenestra: widget power icon
                    contentItem: RowLayout {   // icon in the theme's text color
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-suspend-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Sleep")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // power-highlight-v1
                        border.width: 1                 // same border as the other highlights
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.suspend();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canHibernate === true && Plasmoid.configuration.showHibernateButton   // 2.0: only if the system can hibernate
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-hibernate-v2.svg")   // Fenestra: widget power icon
                    contentItem: RowLayout {   // icon in the theme's text color
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-hibernate-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Hibernate")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // power-highlight-v1
                        border.width: 1                 // same border as the other highlights
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.hibernate();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canShutdown && Plasmoid.configuration.showShutdownButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-shutdown-v2.svg")   // Fenestra: widget power icon
                    contentItem: RowLayout {   // icon in the theme's text color
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-shutdown-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Shut down")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // power-highlight-v1
                        border.width: 1                 // same border as the other highlights
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.requestShutdown();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canReboot && Plasmoid.configuration.showRestartButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-reboot-v2.svg")   // Fenestra: widget power icon
                    contentItem: RowLayout {   // icon in the theme's text color
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-reboot-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Restart")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // power-highlight-v1
                        border.width: 1                 // same border as the other highlights
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.requestReboot();
                    }
                }
            }
        }
            }
        }
    }

    
}
