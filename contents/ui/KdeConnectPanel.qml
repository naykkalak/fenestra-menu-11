/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * SPDX-FileCopyrightText: 2026 naykkalak
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
 * Fenestra Menu 11 — "Mobile device" panel (KDE Connect), Windows 11 style.
 * Separate window attached to the right edge of the menu (or the left if there is no room),
 * same height as the menu. Opened/closed by the button to the right of the search.
 *
 * Step 2: actions (ring, files, browse, clipboard, SMS, ping).
 * Step 1: detection of paired devices, header (name, state, battery),
 *           "no device" screen + Android / iPhone guides.
 * Data goes through D-Bus (qdbus6 / qdbus-qt6 / qdbus), nothing is hard-coded.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import QtQuick.Effects
import QtCore   // StandardPaths (theme's KDE Connect icon)
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg   // theme tooltip drawing
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid   // Fenestra: widget settings

PlasmaCore.Dialog {
    id: panel

    // main menu window (set by MenuRepresentation.qml)
    property var menuWindow: null

    flags: Qt.WindowStaysOnTopHint
    // 2.1.1: attached to the edge of the bar (KWin slides it in and out) + floating (four rounded corners)
    location: (Plasmoid.location === PlasmaCore.Types.BottomEdge || Plasmoid.location === PlasmaCore.Types.TopEdge || Plasmoid.location === PlasmaCore.Types.LeftEdge || Plasmoid.location === PlasmaCore.Types.RightEdge) ? Plasmoid.location : PlasmaCore.Types.Floating
    floating: 1
    hideOnWindowDeactivate: false
    visible: false

    // ── State ──────────────────────────────────────────────────────────────
    property var devices: []          // [{id, name, type, reachable, charge, charging}]
    property int current: 0
    property bool loaded: false
    property bool noQdbus: false
    property string page: "auto"      // "auto" | "android" | "iphone"
    property bool busy: false         // file picker open: do not close everything
    property bool hold: false          // a small menu window is open: panel on hold
    property bool smsOpen: false
    property bool linkOpen: false        // "Send a link" form
    property string toast: ""
    readonly property bool online: dev !== null && dev.reachable
    readonly property var dev: devices.length > 0 ? devices[Math.min(current, devices.length - 1)] : null
    readonly property bool hasPhoto: dev !== null && dev.plugins.indexOf("kdeconnect_photo") >= 0
    readonly property bool hasMedia: online && dev.mTitle !== ""
    readonly property bool hasNetwork: online && dev.netType !== "" && dev.netStrength >= 0

    // Fenestra: toggle button: the state is kept in the widget settings
    function toggle() {
        Plasmoid.configuration.kdeConnectPanelOn = !visible;
        if (visible) close(); else open();
    }
    // 2.0: tooltip drawn inside the panel (Plasma 6.8 misplaces the tooltips of this window)
    property Item infoCible: null
    property string infoTexte: ""
    function infobulle(cible, texte) {
        if (texte === "") { if (infoCible === cible) { infoCible = null; infoTexte = ""; } return; }
        infoCible = cible; infoTexte = texte;
    }
    // menu opened with the panel active: reopens as soon as the menu is active
    property bool aRouvrir: false
    property int retardOuverture: 0   // Fenestra: panel opening delay (ms)
    readonly property int recentrageVolet: 4   // Fenestra: panel recentering (px to the left)
    function rouvrirSiActif() {
        if (!aRouvrir || !menuWindow || !menuWindow.visible || visible) return;
        aRouvrir = false;
        graceVolet.restart();
        open();
        Qt.callLater(function () { if (menuWindow && menuWindow.visible) menuWindow.requestActivate(); });
    }

    function open() {
        hold = false;
        if (!menuWindow) return;
        page = "auto";
        smsOpen = false;
        linkOpen = false;
        toast = "";
        menuWindow.hideOnWindowDeactivate = false;
        visible = true;
        refresh();
    }

    // closes the panel without touching the menu (another menu window opens)
    function closeQuiet() { plusMenu.visible = false; if (visible) visible = false; }

    function close() {
        plusMenu.visible = false;
        if (!visible) return;
        visible = false;
        if (menuWindow) {
            menuWindow.hideOnWindowDeactivate = true;
            if (menuWindow.visible) menuWindow.requestActivate();
        }
    }

    onVisibleChanged: if (visible) Qt.callLater(reposition)

    // Native menu closing (hideOnWindowDeactivate):
    // disabled only while the mouse is over the panel (so that it can be clicked),
    // re-enabled as soon as the mouse leaves it AND the menu is active.
    // This native mechanism is what detects a click on the taskbar.
    function syncFlag() {
        if (!menuWindow || !visible) return;
        // Fenestra: native closing disabled during the grace delay
        var natif = menuWindow.active && !voletHover.hovered && !busy && !hold && !graceVolet.running;
        if (menuWindow.hideOnWindowDeactivate !== natif)
            menuWindow.hideOnWindowDeactivate = natif;
    }
    onBusyChanged: syncFlag()
    onHoldChanged: { if (!hold) graceVolet.restart(); syncFlag(); }   // Fenestra: grace delay after a small window

    onActiveChanged: syncFlag()

    // the panel gives focus back to the menu right AFTER a click (on release):
    // never during it, otherwise the click would be cut in two and lost.
    // Exceptions: SMS input and file picker (they need the keyboard).
    function rendreFocus() {
        if (!active || !menuWindow || !menuWindow.visible) return;
        if (smsOpen || linkOpen || notifReplying !== "" || busy || hold) return;
        menuWindow.requestActivate();
    }

    function reposition() {
        if (!menuWindow) return;
        var gap = Kirigami.Units.smallSpacing * 2;
        // Fenestra: menu's screen (on the 1st click, the panel is not yet on the right screen)
        var mi = menuWindow.mainItem;
        var ecran = (mi && mi.Screen.width > 0) ? mi.Screen : content.Screen;
        var ecranDroite = ecran.virtualX + ecran.width;
        var ecranGauche = ecran.virtualX;
        var nx = menuWindow.x + menuWindow.width + gap;
        if (nx + width > ecranDroite)
            nx = Math.max(ecranGauche, menuWindow.x - width - gap);
        x = nx;
        y = menuWindow.y;
    }


    // ── Reading the devices over D-Bus ─────────────────────────────────────
    readonly property string readCmd:
        "sh -c 'Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
        "[ -n \"$Q\" ] || { echo NOQDBUS; exit 0; }; " +
        "S=org.kde.kdeconnect; P=/modules/kdeconnect; " +
        "for i in $($Q $S $P org.kde.kdeconnect.daemon.devices false true 2>/dev/null); do " +
        "n=$($Q $S $P/devices/$i org.kde.kdeconnect.device.name 2>/dev/null); " +
        "t=$($Q $S $P/devices/$i org.kde.kdeconnect.device.type 2>/dev/null); " +
        "r=$($Q $S $P/devices/$i org.kde.kdeconnect.device.isReachable 2>/dev/null); " +
        "c=$($Q $S $P/devices/$i/battery org.kde.kdeconnect.device.battery.charge 2>/dev/null); " +
        "g=$($Q $S $P/devices/$i/battery org.kde.kdeconnect.device.battery.isCharging 2>/dev/null); " +
        // loaded modules (photo…), mobile network, music playing on the phone
        "lp=$($Q $S $P/devices/$i org.kde.kdeconnect.device.loadedPlugins 2>/dev/null | tr \"\\n\" \",\"); " +
        "ct=$($Q $S $P/devices/$i/connectivity_report org.kde.kdeconnect.device.connectivity_report.cellularNetworkType 2>/dev/null); " +
        "cs=$($Q $S $P/devices/$i/connectivity_report org.kde.kdeconnect.device.connectivity_report.cellularNetworkStrength 2>/dev/null); " +
        "M=$P/devices/$i/mprisremote; I=org.kde.kdeconnect.device.mprisremote; " +
        "$Q $S $M $I.requestPlayerList >/dev/null 2>&1; " +
        "pl=$($Q $S $M $I.playerList 2>/dev/null | head -n1); pc=$($Q $S $M $I.player 2>/dev/null); " +
        "[ -z \"$pc\" ] && [ -n \"$pl\" ] && $Q $S $M $I.player \"$pl\" >/dev/null 2>&1; " +
        "mt=$($Q $S $M $I.title 2>/dev/null | tr \"\\t\\n\" \"  \"); " +
        "ma=$($Q $S $M $I.artist 2>/dev/null | tr \"\\t\\n\" \"  \"); " +
        "mp=$($Q $S $M $I.isPlaying 2>/dev/null); " +
        "ml=$($Q $S $M $I.length 2>/dev/null); mo=$($Q $S $M $I.position 2>/dev/null); " +
        "mk=$($Q $S $M $I.canSeek 2>/dev/null); mv=$($Q $S $M $I.volume 2>/dev/null); " +
        "printf \"%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n\" " +
        "\"$i\" \"$n\" \"$t\" \"$r\" \"${c:--1}\" \"$g\" \"$lp\" \"$ct\" \"${cs:--1}\" \"$mt\" \"$ma\" \"$mp\" " +
        "\"${ml:-0}\" \"${mo:-0}\" \"$mk\" \"${mv:--1}\"; done'"

    function refresh() { reader.connectSource(readCmd + " #" + Date.now()); }
    function run(cmd)   { runner.connectSource(cmd + " #" + Date.now()); }

    // ── Actions ─────────────────────────────────────────────────────────────
    // Fluent UI icons (MIT) stored in the widget: contents/icons/kdeconnect/
    function ico(n) { return Qt.resolvedUrl("../icons/kdeconnect/" + n + ".svg"); }

    function shq(t) { return "'" + String(t).replace(/'/g, "'\\''") + "'"; }
    function cli(args) { return "kdeconnect-cli -d " + shq(dev.id) + " " + args; }
    function say(t) { toast = t; toastTimer.restart(); }

    function doRing()      { if (!online) return; run(cli("--ring")); say(i18n("The phone is ringing…")); }
    function doPing()      { if (!online) return; run(cli("--ping-msg " + shq(i18n("Hello from the PC")))); say(i18n("Ping sent")); }
    function doClipboard() { if (!online) return; run(cli("--send-clipboard")); say(i18n("Clipboard sent")); }
    function doBrowse() {
        if (!online) return;
        var id = shq(dev.id);
        run("sh -c " + shq("kdeconnect-cli -d " + id + " --mount; " +
            "for n in 1 2 3 4 5 6; do p=$(kdeconnect-cli -d " + id + " --get-mount-point 2>/dev/null); " +
            "[ -n \"$p\" ] && [ -d \"$p\" ] && ls \"$p\" >/dev/null 2>&1 && break; sleep 1; done; " +
            "[ -n \"$p\" ] && dolphin --new-window \"$p\""));
        say(i18n("Opening the phone's files…"));
    }
    function doFiles() {
        if (!online) return;
        busy = true;
        fileDialog.open();
    }
    function sendFiles(urls) {
        for (var k = 0; k < urls.length; k++)
            run(cli("--share " + shq(urls[k].toString())));
        say(i18np("File sent", "%1 files sent", urls.length));
    }
    // web link -> opened on the phone; other text -> sent as text
    function sendLink(texte) {
        var t = String(texte).trim();
        if (!online || t === "") return false;
        if (/^(https?:\/\/|www\.)/i.test(t)) {
            var url = /^www\./i.test(t) ? "https://" + t : t;
            run(cli("--share " + shq(url)));
            say(i18n("Link sent: it opens on the phone"));
        } else {
            run(cli("--share-text " + shq(t)));
            say(i18n("Text sent"));
        }
        return true;
    }

    // photo taken with the phone, stored in Pictures/KDE Connect,
    // then opened on the PC as soon as it arrives (waits up to 90 s)
    function doPhoto() {
        if (!online || !hasPhoto) return;
        run("sh -c " + shq(
            "d=$(xdg-user-dir PICTURES 2>/dev/null); [ -d \"$d\" ] || d=\"$HOME/Images\"; " +
            "d=\"$d/KDE Connect\"; mkdir -p \"$d\"; " +
            "f=\"$d/photo-$(date +%Y%m%d-%H%M%S).jpg\"; " +
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + dev.id +
            "/photo org.kde.kdeconnect.device.photo.requestPhoto \"file://$f\" || exit 1; " +
            "for n in $(seq 1 90); do [ -s \"$f\" ] && { sleep 1; xdg-open \"$f\"; exit 0; }; sleep 1; done"));
        say(i18n("Take the photo on the phone: it will open here."));
    }

    // media commands: PlayPause, Next, Previous
    function media(action) {
        if (!hasMedia) return;
        run("sh -c " + shq(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + dev.id +
            "/mprisremote org.kde.kdeconnect.device.mprisremote.sendAction " + action));
    }

    function doSettings() { run("kdeconnect-app"); }

    // track position (ms), advanced second by second between two readings
    property real mediaPos: 0
    property real volAvantMuet: 40
    readonly property bool hasProgress: hasMedia && dev.mLength > 0
    readonly property bool hasVolume: hasMedia && dev.mVolume >= 0

    function fmtTime(ms) {
        var t = Math.max(0, Math.floor(ms / 1000));
        var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60;
        var ss = (sec < 10 ? "0" : "") + sec;
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
    }

    function mprisSet(prop, value) {
        run("sh -c " + shq(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + dev.id +
            "/mprisremote org.kde.kdeconnect.device.mprisremote." + prop + " " + value));
    }

    function seekTo(ms) {
        if (!hasProgress || !dev.mSeek) return;
        mediaPos = Math.max(0, Math.min(dev.mLength, ms));
        mprisSet("position", Math.round(mediaPos));
    }

    // Mute: phone volume set to 0 while remembering the previous value; a second click restores it
    function toggleMute() {
        if (!hasMedia || dev.mVolume < 0) return;
        if (dev.mVolume > 0) {
            volAvantMuet = dev.mVolume;
            mprisSet("volume", 0);
        } else {
            mprisSet("volume", Math.max(1, Math.round(volAvantMuet)));
        }
        // close successive readings: the phone takes a moment to confirm its new volume
        run("sleep 0.7"); run("sleep 1.5"); run("sleep 2.5");
    }

    // The phone adjusts its volume in steps (often 15, i.e. ~6.7%) and rounds
    // to the nearest step: a 7% increment crosses exactly one step.
    // The display always shows the phone's REAL value (read back right afterwards).
    function volumeStep(delta) {
        if (!hasMedia || dev.mVolume < 0) return;
        mprisSet("volume", Math.max(0, Math.min(100, dev.mVolume + delta)));
    }

    // ── Phone notifications (mirror: nothing is kept on disk) ──
    // read with busctl (one call per notification); permanent
    // notifications (cannot be removed: music, services…) are discarded
    property var notifs: []            // [{id, app, title, text, reply, icon}]
    property string notifReplying: ""  // id of the notification being replied to
    readonly property bool hasNotifPlugin: online && dev.plugins.indexOf("kdeconnect_notifications") >= 0

    readonly property string lecteurNotifs: "import json, subprocess, sys\nbase = \"/modules/kdeconnect/devices/\" + sys.argv[1] + \"/notifications\"\ndef call(path, iface, method, *args):\n    try:\n        r = subprocess.run([\"busctl\", \"--user\", \"--json=short\", \"call\", \"org.kde.kdeconnect\",\n                            path, iface, method] + list(args), capture_output=True, text=True, timeout=5)\n        return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None\n    except Exception:\n        return None\nr = call(base, \"org.kde.kdeconnect.device.notifications\", \"activeNotifications\")\nids = r[\"data\"][0] if r else []\nout = []\nfor i in ids:\n    g = call(base + \"/\" + i, \"org.freedesktop.DBus.Properties\", \"GetAll\", \"s\",\n             \"org.kde.kdeconnect.device.notifications.notification\")\n    if not g:\n        continue\n    p = {k: v.get(\"data\") for k, v in g[\"data\"][0].items()}\n    if not p.get(\"dismissable\"):\n        continue\n    out.append({\"id\": i, \"app\": p.get(\"appName\") or \"\", \"title\": p.get(\"title\") or \"\",\n                \"text\": p.get(\"text\") or \"\", \"reply\": p.get(\"replyId\") or \"\",\n                \"icon\": (p.get(\"iconPath\") or \"\") if p.get(\"hasIcon\") else \"\"})\nout.sort(key=lambda n: int(n[\"id\"]) if n[\"id\"].isdigit() else 0, reverse=True)\nprint(json.dumps(out))\n"

    function refreshNotifs() {
        if (!hasNotifPlugin) { notifs = []; return; }
        notifSource.connectSource("sh -c " + shq("python3 -c " + shq(lecteurNotifs) + " " + shq(dev.id)) +
                                  " #" + Date.now());
    }

    function notifCall(id, method, arg) {
        run("sh -c " + shq(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + dev.id + "/notifications/" + id +
            " org.kde.kdeconnect.device.notifications.notification." + method +
            (arg !== undefined ? " " + shq(arg) : "")));
    }

    // dismiss = swipe the notification away: the message itself is not deleted
    function dismissNotif(id) {
        notifCall(id, "dismiss");
        notifs = notifs.filter(function (n) { return n.id !== id; });
        if (notifReplying === id) notifReplying = "";
    }

    function dismissAllNotifs() {
        for (var k = 0; k < notifs.length; k++) notifCall(notifs[k].id, "dismiss");
        notifs = [];
        notifReplying = "";
    }

    function replyNotif(id, msg) {
        if (String(msg).trim() === "") return false;
        notifCall(id, "sendReply", msg);
        notifReplying = "";
        say(i18n("Reply sent"));
        return true;
    }

    // ── Contacts (vCard files synchronized by KDE Connect) ──
    // read when the SMS form opens, kept in memory only
    property var contacts: []          // [{name, number, type, key, digits}]
    property var smsSuggestions: []
    property string smsContact: ""     // "Marie (mobile)" once chosen

    readonly property string lecteurContacts: "import sys, os, glob, quopri\nout = set()\nfor f in glob.glob(os.path.join(sys.argv[1], \"*.vcf\")):\n    try:\n        raw = open(f, \"rb\").read().decode(\"utf-8\", \"replace\").replace(\"\\r\\n\", \"\\n\")\n    except Exception:\n        continue\n    lignes = []\n    for l in raw.split(\"\\n\"):\n        if lignes and l[:1] in (\" \", \"\\t\"):\n            lignes[-1] += l[1:]\n            continue\n        if lignes and lignes[-1].endswith(\"=\") and \"QUOTED-PRINTABLE\" in lignes[-1].split(\":\", 1)[0].upper():\n            lignes[-1] = lignes[-1][:-1] + l\n            continue\n        lignes.append(l)\n    nom, tels = \"\", []\n    for l in lignes:\n        if \":\" not in l:\n            continue\n        k, v = l.split(\":\", 1)\n        parts = k.split(\";\")\n        cle, params = parts[0].upper(), \";\".join(parts[1:]).upper()\n        if \"QUOTED-PRINTABLE\" in params:\n            v = quopri.decodestring(v.encode()).decode(\"utf-8\", \"replace\")\n        if cle == \"FN\":\n            nom = v.strip()\n        elif cle == \"TEL\":\n            t = \"mobile\" if \"CELL\" in params else \"domicile\" if \"HOME\" in params else \"travail\" if \"WORK\" in params else \"\"\n            tels.append((v.strip(), t))\n    for num, t in tels:\n        if nom and num:\n            out.add((nom.replace(\"\\t\", \" \"), num, t))\nfor n, num, t in sorted(out, key=lambda x: x[0].lower()):\n    print(n + \"\\t\" + num + \"\\t\" + t)\n"

    function loadContacts() {
        if (!dev) return;
        var dossier = "$HOME/.local/share/kpeoplevcard/kdeconnect-" + dev.id;
        contactsSource.connectSource("sh -c " + shq("python3 -c " + shq(lecteurContacts) +
                                     " \"" + dossier + "\"") + " #" + Date.now());
    }

    function sansAccents(t) {
        var r = String(t).toLowerCase();
        try { r = r.normalize("NFD").replace(/[\u0300-\u036f]/g, ""); } catch (e) {}
        return r;
    }

    function filterContacts(q) {
        var n = sansAccents(q).trim();
        var chiffres = n.replace(/[^0-9]/g, "");
        // French numbers: 06… and +33 6… are equivalent
        var autre = chiffres.indexOf("0") === 0 ? "33" + chiffres.slice(1)
                  : chiffres.indexOf("33") === 0 ? "0" + chiffres.slice(2) : "";
        var res = [];
        if (n === "") { smsSuggestions = []; return; }
        for (var i = 0; i < contacts.length && res.length < 6; i++) {
            var c = contacts[i];
            var parNom = c.key.indexOf(n) >= 0;
            var parNum = chiffres.length >= 3 && /^[+0-9 .\-()]+$/.test(n)
                         && (c.digits.indexOf(chiffres) >= 0 || (autre !== "" && c.digits.indexOf(autre) >= 0));
            if (parNom || parNum) res.push(c);
        }
        smsSuggestions = res;
    }

    // French-style display: 06 35 93 98 41  /  +336 35 93 98 41
    // (foreign or short numbers: left as they are)
    function fmtNumero(num) {
        var brut = String(num).trim();
        var d = brut.replace(/[^0-9]/g, "");
        function paires(t) { return t.replace(/(\d{2})(?=\d)/g, "$1 "); }
        if (/^\+/.test(brut) && d.length === 11 && d.indexOf("33") === 0)
            return "+33" + d.charAt(2) + " " + paires(d.slice(3));
        if (d.length === 10 && d.charAt(0) === "0")
            return paires(d);
        return brut;
    }

    function pickContact(c) {
        smsContact = c.name + (c.type !== "" ? " (" + c.type + ")" : "");
        smsSuggestions = [];
    }

    onSmsOpenChanged: {
        smsContact = "";
        smsSuggestions = [];
        if (smsOpen) {
            smsNumber.text = "";        // new recipient on every opening
            loadContacts();
        }
    }

    function sendSms(num, msg) {
        if (!online || num.trim() === "" || msg.trim() === "") return false;
        if (num.replace(/[^0-9]/g, "").length < 3) {        // a name, not a number
            say(i18n("Choose a contact from the list or type a number"));
            return false;
        }
        smsEnCours = true;
        say(i18n("Sending SMS…"));
        // "echo CODE=$?": the command tells whether the phone really received the send order
        var propre = num.trim().replace(/[\s.\-()]/g, "");   // 06 35… -> 0635…
        smsSource.connectSource("sh -c " + shq(cli("--destination " + shq(propre) +
                                " --send-sms " + shq(msg)) + "; echo CODE=$?") + " #" + Date.now());
        return true;
    }
    property bool smsEnCours: false


    // ── Small components in the theme's style ─────────────────────────────
    // widget Fluent icon: the SVG serves as a stencil (mask), filled with the
    // theme's text color. Read directly from the file: Plasma cannot
    // substitute a theme icon with the same name for it.
    component FluentIcon: Item {
        id: fi
        property string src: ""
        property color tint: Kirigami.Theme.textColor
        Image {
            id: fiForme
            anchors.fill: parent
            source: fi.src
            sourceSize.width: Math.max(1, fi.width) * 2
            sourceSize.height: Math.max(1, fi.height) * 2
            smooth: true
            visible: false
        }
        Rectangle {
            id: fiCouleur
            anchors.fill: parent
            color: fi.tint
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: fiCouleur
            maskEnabled: true
            maskSource: fiForme
            // threshold at half transparency + soft transition: the anti-aliased edges
            // keep their thinness (otherwise every stroke gets one pixel thicker)
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // row of the "···" window: same layout as the Power window
    // (22 px icon, margins, white 50% rounded highlight on hover)
    component PlusItem: Item {
        id: pi
        property string label: ""
        property string icone: ""          // widget Fluent icon
        property string iconeFichier: ""   // or a specific icon file (takes priority)
        signal clicked()
        Layout.fillWidth: true
        implicitWidth: piRow.implicitWidth + (Kirigami.Units.smallSpacing + 6) * 2
        implicitHeight: Math.max(22, piText.implicitHeight) + Kirigami.Units.smallSpacing * 2
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Kirigami.Units.smallSpacing
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1                 // same border as the other highlights
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: piMouse.containsMouse ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Row {
            id: piRow
            x: Kirigami.Units.smallSpacing + 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Kirigami.Units.smallSpacing + 6
            FluentIcon {
                visible: pi.iconeFichier === ""
                src: pi.iconeFichier === "" ? panel.ico(pi.icone) : ""
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
            }
            Kirigami.Icon {
                visible: pi.iconeFichier !== ""
                source: pi.iconeFichier
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: piText
                text: pi.label
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: piMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pi.clicked()
        }
    }

    // button: white 50% highlight + border on hover
    component PanelButton: Item {
        id: pb
        property string text: ""
        property string iconName: ""
        property bool framed: true          // frame visible at rest (Android / iPhone buttons)
        readonly property bool fluent: iconName.indexOf("/icons/kdeconnect/") >= 0
        readonly property bool hovered: pbMouse.containsMouse
        property bool press: false      // press effect on click
        // Fenestra: the icon spins for 2 s after a click (Refresh button); click ignored meanwhile
        property bool tournerAuClic: false
        property string tip: ""   // 2.0: tooltip drawn inside the panel (Plasma 6.8 misplaces the tooltips of this window)
        onHoveredChanged: panel.infobulle(pb, hovered ? pb.tip : "")
        property bool tourne: false
        Timer { id: pbTour; interval: 2000; onTriggered: pb.tourne = false }
        signal clicked()
        implicitWidth: pbRow.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: Math.max(28, pbRow.implicitHeight + Kirigami.Units.smallSpacing * 2)
        Accessible.role: Accessible.Button
        Accessible.name: text

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (pbMouse.containsMouse || pb.framed) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Row {
            id: pbRow
            anchors.centerIn: parent
            scale: (pb.press && pbMouse.pressed) ? 0.85 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: pb.iconName !== "" && !pb.fluent
                source: pb.fluent ? "" : pb.iconName
                width: Kirigami.Units.iconSizes.small; height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            FluentIcon {
                id: pbFluent
                visible: pb.fluent
                src: pb.fluent ? pb.iconName : ""
                width: pb.tournerAuClic ? Math.round(Kirigami.Units.iconSizes.small * 1.25) : Kirigami.Units.iconSizes.small; height: width   // refresh-size (2.0): 20 px, the icon's native size
                anchors.verticalCenter: parent.verticalCenter
                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: pb.tourne
                    onRunningChanged: if (!running) pbFluent.rotation = 0
                }
            }
            Text {
                visible: pb.text !== ""   // refresh-center (2.0): no space reserved for an empty text
                text: pb.text
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                panel.infobulle(pb, "");
                if (pb.tournerAuClic) {
                    if (pb.tourne)
                        return;
                    pb.tourne = true;
                    pbTour.restart();
                }
                pb.clicked();
            }
        }
    }

    // action tile: icon + label, white 50% highlight on hover
    component ActionTile: Item {
        id: at
        FontMetrics { id: atMetrics; font: Kirigami.Theme.smallFont }
        property string text: ""
        property string iconName: ""
        property bool active: true
        readonly property bool fluent: iconName.indexOf("/icons/kdeconnect/") >= 0
        signal clicked()
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        + atMetrics.height * 2 + Kirigami.Units.largeSpacing * 2
        opacity: active ? 1.0 : 0.4
        Accessible.role: Accessible.Button
        Accessible.name: text

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (atMouse.containsMouse && at.active) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Column {
            id: atCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Kirigami.Units.largeSpacing
            width: parent.width - Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: !at.fluent
                anchors.horizontalCenter: parent.horizontalCenter
                source: at.fluent ? "" : at.iconName
                width: Kirigami.Units.iconSizes.smallMedium; height: width
                scale: atMouse.pressed && at.active ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
            }
            FluentIcon {
                visible: at.fluent
                anchors.horizontalCenter: parent.horizontalCenter
                src: at.fluent ? at.iconName : ""
                width: Kirigami.Units.iconSizes.smallMedium; height: width
                scale: atMouse.pressed && at.active ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: at.text
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        MouseArea {
            id: atMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: at.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (at.active) at.clicked()
        }
    }

    // drawn illustration (laptop + phone), in the theme's colors
    component Illustration: Item {
        implicitWidth: 170
        implicitHeight: 110
        // laptop screen
        Rectangle {
            id: laptop
            x: 0; y: 8
            width: 130; height: 84
            radius: 6
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b, 0.35)
            border.width: 3
            border.color: "#5A5A5A"
            Rectangle {   // small "notifications" on the screen
                x: 14; y: 30; width: 16; height: 16; radius: 4; color: "#F2A33A"
            }
            Rectangle { x: 34; y: 30; width: 16; height: 16; radius: 4; color: "#3DAEE6" }
            Rectangle { x: 54; y: 30; width: 40; height: 16; radius: 4; color: "#ffffff"; opacity: 0.9 }
        }
        // laptop base
        Rectangle {
            x: -8; y: laptop.y + laptop.height - 1
            width: laptop.width + 16; height: 7; radius: 3
            color: "#8A8A8A"
        }
        // phone
        Rectangle {
            x: 108; y: 0
            width: 52; height: 100
            radius: 9
            color: "#3A3A3A"
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 6
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, 0.75)
            }
        }
    }

    // ── Panel content ──────────────────────────────────────────────────────
    mainItem: Item {
        id: content
        width: Kirigami.Units.gridUnit * 16
        height: panel.menuWindow
                ? Math.max(Kirigami.Units.gridUnit * 12,
                           panel.menuWindow.height - panel.margins.top - panel.margins.bottom)
                : Kirigami.Units.gridUnit * 20

        focus: true
        Keys.onEscapePressed: panel.close()

        // 2.0: tooltip drawn inside the panel (Plasma 6.8 misplaces the tooltips of this window)
        Item {
            id: bulleInfo
            z: 1000
            visible: delaiInfo.ecoule && panel.infoCible !== null && panel.infoTexte !== ""
            readonly property point pt: panel.infoCible ? panel.infoCible.mapToItem(content, 0, 0) : Qt.point(0, 0)
            width: bulleTexte.implicitWidth + bulleFond.margins.left + bulleFond.margins.right
            height: bulleTexte.implicitHeight + bulleFond.margins.top + bulleFond.margins.bottom
            x: panel.infoCible ? Math.max(4, Math.min(content.width - width - 4, pt.x + panel.infoCible.width / 2 - width / 2)) : 0
            y: panel.infoCible ? ((pt.y - height - 4 >= 4) ? pt.y - height - 4 : pt.y + panel.infoCible.height + 4) : 0
            Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip   // theme tooltip colors, like all the others
            Kirigami.Theme.inherit: false
            Rectangle {   // soft shadow around the bubble
                z: -1
                anchors.fill: parent
                anchors.margins: -1
                radius: 7
                color: Qt.rgba(0, 0, 0, 0.05)
                Rectangle { z: -1; anchors.fill: parent; anchors.margins: -2; radius: 9; color: Qt.rgba(0, 0, 0, 0.035)
                    Rectangle { z: -1; anchors.fill: parent; anchors.margins: -2; radius: 11; color: Qt.rgba(0, 0, 0, 0.025) } }
            }
            KSvg.FrameSvgItem {   // the Plasma theme's tooltip drawing: same look as all the tooltips
                id: bulleFond
                anchors.fill: parent
                imagePath: "widgets/tooltip"
            }
            Text {
                id: bulleTexte
                x: bulleFond.margins.left
                y: bulleFond.margins.top
                text: panel.infoTexte
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
            }
        }
        Timer { id: delaiInfo; interval: 400; property bool ecoule: false; onTriggered: ecoule = true }
        Connections {
            target: panel
            function onInfoTexteChanged() {
                delaiInfo.stop(); delaiInfo.ecoule = false;
                if (panel.infoTexte !== "") delaiInfo.start();
            }
        }

        // non-visual objects (a Dialog accepts only its mainItem as a child)
        // the menu closes -> the panel too; the menu moves -> we follow
        // panel hover (works without focus)
        HoverHandler {
            id: voletHover
            onHoveredChanged: panel.syncFlag()
        }

        // after every click in the panel (on release, once the action is done),
        // focus is given back to the menu: KWin accepts it because it follows a click
        // (a simple mouse movement would be refused under Wayland).
        // Passive handle: it observes the clicks without ever intercepting them.
        PointHandler {
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (!active) Qt.callLater(panel.rendreFocus)
        }

        Connections {
            target: panel.menuWindow
            function onActiveChanged() { panel.syncFlag(); }
            function onVisibleChanged() {
                if (!panel.menuWindow.visible) { panel.aRouvrir = false; panel.close(); }
                else { panel.aRouvrir = Plasmoid.configuration.kdeConnectMemoriser && Plasmoid.configuration.kdeConnectPanelOn; retardVolet.restart(); }
            }
            function onXChanged() { if (panel.visible) Qt.callLater(panel.reposition); }
            function onYChanged() { if (panel.visible) Qt.callLater(panel.reposition); }
            function onHeightChanged() { if (panel.visible) Qt.callLater(panel.reposition); }
        }

        // Fenestra: grace delay at opening: menu and panel appear together,
        // the monitoring below waits until they are in place
        Timer { id: graceVolet; interval: 600; onTriggered: panel.syncFlag() }
        Timer { id: retardVolet; interval: panel.retardOuverture; onTriggered: panel.rouvrirSiActif() }
        // Fenestra: phone preloading: 3 s after startup, panel closed (content ready at the 1st opening)
        Timer { id: prechargementVolet; interval: 3000; running: true; onTriggered: if (!panel.visible) panel.refresh() }

        // click outside the menu AND the panel -> everything closes
        Timer {
            interval: 250
            repeat: true
            running: panel.visible
            onTriggered: {
                if (!panel.menuWindow) return;
                panel.syncFlag();
                if (panel.busy || panel.hold || graceVolet.running) return;
                if (!panel.active && !panel.menuWindow.active) {
                    panel.close();
                    panel.menuWindow.visible = false;
                }
            }
        }

        // regular refresh while the panel is open
        Timer {
            interval: 5000
            repeat: true
            running: panel.visible
            onTriggered: panel.refresh()
        }

        P5Support.DataSource {
            id: reader
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                var out = (data["stdout"] || "").trim();
                panel.noQdbus = (out === "NOQDBUS");
                var list = [];
                if (!panel.noQdbus && out !== "") {
                    var lines = out.split("\n");
                    for (var k = 0; k < lines.length; k++) {
                        var f = lines[k].split("\t");
                        if (f.length < 6 || f[0] === "") continue;
                        var force = parseInt(f[8]);
                        list.push({ id: f[0], name: f[1] || f[0], type: f[2],
                                    reachable: f[3] === "true",
                                    charge: parseInt(f[4]), charging: f[5] === "true",
                                    plugins: (f[6] || "").split(","),
                                    netType: (f[7] || "").trim(),
                                    netStrength: isNaN(force) ? -1 : force,
                                    mTitle: (f[9] || "").trim(),
                                    mArtist: (f[10] || "").trim(),
                                    mPlaying: f[11] === "true",
                                    mLength: parseInt(f[12]) || 0,
                                    mPos: parseInt(f[13]) || 0,
                                    mSeek: f[14] === "true",
                                    mVolume: isNaN(parseInt(f[15])) ? -1 : parseInt(f[15]) });
                    }
                }
                // keeps the chosen device if it still exists
                var keepId = panel.dev ? panel.dev.id : "";
                panel.devices = list;
                var idx = 0;
                for (var j = 0; j < list.length; j++) if (list[j].id === keepId) idx = j;
                panel.current = idx;
                panel.loaded = true;
                if (panel.dev) panel.mediaPos = panel.dev.mPos;
                panel.refreshNotifs();
            }
        }

        Timer {
            id: toastTimer
            interval: 2500
            onTriggered: panel.toast = ""
        }

        FileDialog {
            id: fileDialog
            title: i18n("Send to phone")
            fileMode: FileDialog.OpenFiles
            onAccepted: {
                panel.sendFiles(selectedFiles);
                panel.busy = false;
                panel.requestActivate();
            }
            onRejected: {
                panel.busy = false;
                panel.requestActivate();
            }
        }

        P5Support.DataSource {
            id: notifSource
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                try {
                    var liste = JSON.parse(String(data["stdout"] || "[]"));
                    if (Array.isArray(liste)) panel.notifs = liste;
                } catch (e) { /* failed reading: we keep the previous list */ }
            }
        }

        P5Support.DataSource {
            id: smsSource
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                panel.smsEnCours = false;
                var ok = /CODE=0\s*$/.test(String(data["stdout"] || ""));
                if (ok) {
                    panel.say(i18n("✓ SMS handed over to the phone"));
                    smsText.text = "";
                    panel.smsOpen = false;
                } else {
                    // the form stays open, the text is kept
                    panel.say(i18n("✗ Failed: SMS not handed over to the phone"));
                }
            }
        }

        P5Support.DataSource {
            id: contactsSource
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                var list = [];
                var lignes = String(data["stdout"] || "").split("\n");
                for (var k = 0; k < lignes.length; k++) {
                    var f = lignes[k].split("\t");
                    if (f.length < 2 || f[0] === "" || f[1] === "") continue;
                    list.push({ name: f[0], number: f[1], type: f[2] || "",
                                key: panel.sansAccents(f[0]),
                                digits: f[1].replace(/[^0-9]/g, "") });
                }
                panel.contacts = list;
            }
        }

        P5Support.DataSource {
            id: runner
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                Qt.callLater(panel.refresh);
            }
        }

        // ----- Page: no paired device (welcome) -----
        ColumnLayout {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -panel.recentrageVolet   // Fenestra: panel recentering
            width: parent.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.largeSpacing
            visible: panel.loaded && panel.devices.length === 0 && panel.page === "auto"

            Illustration { Layout.alignment: Qt.AlignHCenter }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: i18n("Access your mobile device here")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: panel.noQdbus
                      ? i18n("The qdbus tool was not found: unable to talk to KDE Connect.")
                      : i18n("See your phone's battery, files and notifications right in the Start menu, thanks to KDE Connect.")
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.largeSpacing
                text: i18n("Select your device")
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing
                PanelButton { text: "Android"; onClicked: panel.page = "android" }
                PanelButton { text: "iPhone";  onClicked: panel.page = "iphone" }
            }
        }

        // ----- Page: pairing guide (Android or iPhone) -----
        ColumnLayout {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -panel.recentrageVolet   // Fenestra: panel recentering
            width: parent.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.largeSpacing
            visible: panel.page === "android" || panel.page === "iphone"

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: panel.page === "iphone" ? i18n("Connect an iPhone") : i18n("Connect an Android phone")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                lineHeight: 1.2
                text: (panel.page === "iphone"
                       ? i18n("1. Install the KDE Connect app from the App Store.\n")
                       : i18n("1. Install the KDE Connect app from the Play Store or F-Droid.\n"))
                      + i18n("2. Connect the phone to the same Wi-Fi network as this PC (or connect this PC to the phone's hotspot).\n")
                      + i18n("3. In the app, tap the name of this PC, then “Request pairing”.\n")
                      + i18n("4. Accept the request that appears on this PC.")
            }
            Text {
                Layout.fillWidth: true
                visible: panel.page === "iphone"
                wrapMode: Text.WordWrap
                text: i18n("On iPhone, KDE Connect offers fewer features than on Android.")
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                font.italic: true
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing
                PanelButton {
                    text: i18n("Download")
                    iconName: "internet-web-browser"
                    onClicked: Qt.openUrlExternally("https://kdeconnect.kde.org/download.html")
                }
                PanelButton {
                    text: i18n("Search")
                    iconName: panel.ico("refresh")
                    tournerAuClic: true
                    onClicked: panel.run("kdeconnect-cli --refresh")
                }
            }
            PanelButton {
                Layout.alignment: Qt.AlignHCenter
                framed: false
                text: i18n("< Back")
                onClicked: panel.page = "auto"
            }
        }

        // ----- Page: paired device -----
        ColumnLayout {
            anchors.top: parent.top
            anchors.topMargin: Kirigami.Units.gridUnit
            anchors.bottom: piedVolet.top
            anchors.bottomMargin: Kirigami.Units.smallSpacing
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -panel.recentrageVolet   // Fenestra: panel recentering
            width: parent.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.smallSpacing
            visible: panel.dev !== null && panel.page === "auto"

            Illustration {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Kirigami.Units.largeSpacing
            }

            // choix de l'appareil s'il y en a plusieurs
            PC3.ComboBox {
                Layout.fillWidth: true
                visible: panel.devices.length > 1
                model: panel.devices.map(d => d.name)
                currentIndex: panel.current
                onActivated: idx => panel.current = idx
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: panel.dev && panel.dev.type === "tablet" ? "tablet" : "smartphone"
                    Layout.leftMargin: -Math.round(Kirigami.Units.iconSizes.medium * 0.25)   // panel-alignment (2.0): the drawing aligns with the start of the line
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    id: tVoletBloc
                    Layout.fillWidth: true
                    spacing: 0
                    // panel-centering (2.0): the text block is centered between the phone and Refresh (same gap on each side)
                    readonly property int decalage: Math.max(0, Math.round((width - Math.max(tVoletNom.implicitWidth, tVoletEtat.implicitWidth)) / 2))
                    Text {
                        id: tVoletNom
                        Layout.fillWidth: true
                        Layout.leftMargin: tVoletBloc.decalage
                        elide: Text.ElideRight
                        text: panel.dev ? panel.dev.name : ""
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.textColor
                    }
                    RowLayout {
                        id: tVoletEtat
                        Layout.leftMargin: tVoletBloc.decalage
                        spacing: Kirigami.Units.smallSpacing
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: panel.dev && panel.dev.reachable ? "#2ecc71" : "#9A9A9A"
                        }
                        Text {
                            text: panel.dev && panel.dev.reachable ? i18n("Connected") : i18n("Offline")
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        Text {
                            visible: panel.dev && panel.dev.reachable && panel.dev.charge >= 0
                            text: "·"
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        Kirigami.Icon {
                            visible: panel.dev && panel.dev.reachable && panel.dev.charge >= 0
                            source: {
                                if (!panel.dev || panel.dev.charge < 0) return "battery-missing";
                                var lvl = Math.max(0, Math.min(100, Math.round(panel.dev.charge / 10) * 10));
                                return Qt.resolvedUrl("../icons/status/phone-battery-" + ("00" + lvl).slice(-3) + (panel.dev.charging ? "-charging" : "") + ".svg");
                            }
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        Text {
                            visible: panel.dev && panel.dev.reachable && panel.dev.charge >= 0
                            text: panel.dev ? panel.dev.charge + " %" : ""
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        // mobile network: 4 bars (strength 0 to 4) + type (4G, 5G…)
                        Text {
                            visible: panel.hasNetwork
                            text: "·"
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        Row {
                            visible: panel.hasNetwork
                            spacing: 1
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 3
                                    height: 4 + index * 2
                                    anchors.bottom: parent.bottom
                                    radius: 1
                                    color: panel.dev && index < panel.dev.netStrength
                                           ? (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A") : (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.18))
                                }
                            }
                        }
                        Text {
                            visible: panel.hasNetwork
                            text: panel.dev ? panel.dev.netType : ""
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                    }
                }
                PanelButton {
                    framed: false
                    iconName: panel.ico("refresh")
                    tournerAuClic: true
                    Layout.rightMargin: -Math.round(Kirigami.Units.smallSpacing * 1.25)   // panel-alignment (2.0): the drawing aligns with the end of the line
                    implicitWidth: implicitHeight
                    onClicked: panel.run("kdeconnect-cli --refresh")
                    tip: i18n("Refresh")   // 2.0: tooltip drawn inside the panel (Plasma 6.8 misplaces the tooltips of this window)
                }
            }

            Rectangle {   // line
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                height: 1
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1))
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                columns: 3
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                ActionTile { text: i18n("Ring");        iconName: panel.ico("ring");       active: panel.online; onClicked: panel.doRing() }
                ActionTile { text: i18n("Send files"); iconName: panel.ico("send");       active: panel.online; onClicked: panel.doFiles() }
                ActionTile { text: i18n("Browse");           iconName: panel.ico("browse");     active: panel.online; onClicked: panel.doBrowse() }
                ActionTile { text: i18n("Clipboard");      iconName: panel.ico("clipboard");  active: panel.online; onClicked: panel.doClipboard() }
                ActionTile { text: i18n("Send a link");     iconName: panel.ico("link");       active: panel.online; onClicked: { panel.linkOpen = !panel.linkOpen; if (panel.linkOpen) { panel.smsOpen = false; linkField.forceActiveFocus(); } } }
                ActionTile { text: i18n("Take a photo");   iconName: panel.ico("camera");     active: panel.online && panel.hasPhoto; onClicked: panel.doPhoto() }
                ActionTile { text: i18n("SMS");                 iconName: panel.ico("sms");        active: panel.online; onClicked: { panel.smsOpen = !panel.smsOpen; if (panel.smsOpen) { panel.linkOpen = false; smsNumber.forceActiveFocus(); } } }
                ActionTile { text: i18n("Ping");                iconName: panel.ico("ping");       active: panel.online; onClicked: panel.doPing() }
                ActionTile { text: i18n("Settings");            iconName: panel.ico("settings");   active: true;         onClicked: panel.doSettings() }
            }

            // SMS form
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.smsOpen && panel.online
                spacing: Kirigami.Units.smallSpacing

                Text {   // chosen recipient
                    Layout.fillWidth: true
                    visible: panel.smsContact !== ""
                    elide: Text.ElideRight
                    text: i18n("To: %1", panel.smsContact)
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
                PC3.TextField {
                    id: smsNumber
                    Layout.fillWidth: true
                    placeholderText: panel.contacts.length > 0 ? i18n("Name or number") : i18n("Phone number")
                    onTextEdited: {
                        panel.smsContact = "";
                        panel.filterContacts(text);
                    }
                    // Enter: first suggested contact, otherwise move on to the message
                    onAccepted: {
                        if (panel.smsSuggestions.length > 0) {
                            var c = panel.smsSuggestions[0];
                            text = panel.fmtNumero(c.number);
                            panel.pickContact(c);
                        }
                        smsText.forceActiveFocus();
                    }
                }
                // contact suggestions (6 at most)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: panel.smsSuggestions.length > 0
                    spacing: 0
                    Repeater {
                        model: panel.smsSuggestions
                        delegate: Item {
                            id: sug
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: sugCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                                border.width: 1
                                border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                                opacity: sugMouse.containsMouse ? 1.0 : 0.0
                            }
                            Column {
                                id: sugCol
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: sug.modelData.name
                                    font.weight: Font.DemiBold
                                    color: Kirigami.Theme.textColor
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: panel.fmtNumero(sug.modelData.number) + (sug.modelData.type !== "" ? " · " + sug.modelData.type : "")
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                                }
                            }
                            MouseArea {
                                id: sugMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    smsNumber.text = panel.fmtNumero(sug.modelData.number);
                                    panel.pickContact(sug.modelData);
                                    smsText.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
                PC3.ScrollView {
                    id: smsScroll
                    Layout.fillWidth: true
                    // grows with the text (4 to 8 units), then scroll bar
                    Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 4,
                        Math.min(Kirigami.Units.gridUnit * 8,
                                 smsText.contentHeight + smsText.topPadding + smsText.bottomPadding))
                    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

                    PC3.TextArea {
                        id: smsText
                        placeholderText: i18n("Message")
                        wrapMode: TextEdit.Wrap
                        // the visible area follows the cursor while typing
                        onCursorRectangleChanged: {
                            var f = smsScroll.contentItem;
                            if (!f || f.contentY === undefined) return;
                            var r = cursorRectangle;
                            if (r.y < f.contentY)
                                f.contentY = r.y;
                            else if (r.y + r.height + bottomPadding > f.contentY + f.height)
                                f.contentY = r.y + r.height + bottomPadding - f.height;
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing
                    PanelButton {
                        framed: false
                        text: i18n("Cancel")
                        onClicked: panel.smsOpen = false
                    }
                    PanelButton {
                        text: i18n("Send")
                        iconName: panel.ico("send")
                        enabled: !panel.smsEnCours
                        onClicked: panel.sendSms(smsNumber.text, smsText.text)
                    }
                }
            }

            // "Send a link" form
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.linkOpen && panel.online
                spacing: Kirigami.Units.smallSpacing

                PC3.TextField {
                    id: linkField
                    Layout.fillWidth: true
                    placeholderText: i18n("Web link or text to send")
                    onAccepted: if (panel.sendLink(text)) { text = ""; panel.linkOpen = false; }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing
                    PanelButton {
                        framed: false
                        text: i18n("Cancel")
                        onClicked: panel.linkOpen = false
                    }
                    PanelButton {
                        text: i18n("Send")
                        iconName: panel.ico("send")
                        onClicked: if (panel.sendLink(linkField.text)) { linkField.text = ""; panel.linkOpen = false; }
                    }
                }
            }

            // music playing on the phone (visible only during playback)
            Rectangle {   // line
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.hasMedia
                height: 1
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1))
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.hasMedia
                spacing: Kirigami.Units.smallSpacing

                FluentIcon {
                    src: panel.ico("music")
                    Layout.leftMargin: -11 + panel.recentrageVolet   // Fenestra: panel recentering
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: panel.dev ? panel.dev.mTitle : ""
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: panel.dev ? panel.dev.mArtist : ""
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                    }
                }
                PanelButton {
                    framed: false
                    press: true
                    iconName: panel.ico("previous")
                    implicitWidth: implicitHeight
                    onClicked: panel.media("Previous")
                }
                PanelButton {
                    framed: false
                    press: true
                    iconName: panel.ico(panel.dev && panel.dev.mPlaying ? "pause" : "play")
                    implicitWidth: implicitHeight
                    onClicked: panel.media("PlayPause")
                }
                PanelButton {
                    framed: false
                    press: true
                    iconName: panel.ico("next")
                    Layout.rightMargin: -7 - panel.recentrageVolet   // Fenestra: panel recentering
                    implicitWidth: implicitHeight
                    onClicked: panel.media("Next")
                }
            }

            // a single row:  −  +   1:24 ━━━━○──── 3:52
            // (volume on the left; progress on the right, hidden for a live stream)
            RowLayout {
                Layout.fillWidth: true
                visible: panel.hasProgress || panel.hasVolume
                spacing: Kirigami.Units.smallSpacing

                PanelButton {   // volume: mute / sound restored
                    visible: panel.hasVolume
                    framed: false
                    press: true
                    Layout.leftMargin: -13 + panel.recentrageVolet   // Fenestra: panel recentering
                    iconName: (panel.dev && panel.dev.mVolume === 0) ? Qt.resolvedUrl("../icons/status/phone-audio-volume-muted.svg") : "audio-volume-medium"
                    implicitHeight: 26
                    implicitWidth: implicitHeight
                    onClicked: panel.toggleMute()
                }
                PanelButton {   // volume: one step down
                    visible: panel.hasVolume
                    framed: false
                    press: true
                    Layout.leftMargin: -3
                    iconName: panel.ico("subtract")
                    implicitHeight: 26
                    implicitWidth: implicitHeight
                    onClicked: panel.volumeStep(-7)
                }
                PanelButton {   // volume: one step up
                    visible: panel.hasVolume
                    framed: false
                    press: true
                    iconName: panel.ico("add")
                    implicitHeight: 26
                    implicitWidth: implicitHeight
                    onClicked: panel.volumeStep(7)
                }
                Item {          // live stream (no duration): the buttons stay on the left
                    visible: !panel.hasProgress
                    Layout.fillWidth: true
                }

                Timer {   // smooth advance between two readings (every 5 s)
                    interval: 1000
                    repeat: true
                    running: panel.visible && panel.hasProgress && panel.dev.mPlaying
                    onTriggered: panel.mediaPos = Math.min(panel.dev.mLength, panel.mediaPos + 1000)
                }
                Text {
                    visible: panel.hasProgress
                    Layout.leftMargin: panel.hasVolume ? Kirigami.Units.smallSpacing : 0
                    text: panel.fmtTime(panel.mediaPos)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                }
                Item {
                    id: barre
                    visible: panel.hasProgress
                    Layout.fillWidth: true
                    implicitHeight: 14
                    readonly property real ratio: panel.hasProgress
                        ? Math.max(0, Math.min(1, panel.mediaPos / panel.dev.mLength)) : 0

                    Rectangle {   // track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 3; radius: 1.5
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.15))
                    }
                    Rectangle {   // elapsed part
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * barre.ratio; height: 3; radius: 1.5
                        color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? "#006CE0" : Kirigami.Theme.highlightColor   // Fenestra blue (light theme)
                    }
                    Rectangle {   // cursor (on hover, if the position can be changed)
                        visible: barreMouse.containsMouse && panel.dev && panel.dev.mSeek
                        width: 10; height: 10; radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * barre.ratio - width / 2
                        color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? "#006CE0" : Kirigami.Theme.highlightColor   // Fenestra blue (light theme)
                        border.width: 2
                        border.color: "#ffffff"
                    }
                    MouseArea {
                        id: barreMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: panel.dev && panel.dev.mSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => panel.seekTo(mouse.x / width * panel.dev.mLength)
                    }
                }
                Text {
                    visible: panel.hasProgress
                    Layout.rightMargin: -panel.recentrageVolet   // Fenestra: panel recentering
                    text: panel.hasProgress ? panel.fmtTime(panel.dev.mLength) : ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                }
            }


            // confirmation message
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: panel.toast !== "" ? panel.toast
                      : (!panel.online ? i18n("The phone is offline: check that it is on the same network.") : "")
                visible: text !== ""
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                font.italic: panel.toast === ""
            }

            // ── Notifications ─────────────────────────────────────────────
            Rectangle {   // line
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.notifs.length > 0
                height: 1
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1))
            }
            RowLayout {
                Layout.fillWidth: true
                visible: panel.notifs.length > 0
                Text {
                    Layout.fillWidth: true
                    text: i18n("Recent notifications")
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
            }
            // the 3 most recent at most (the panel is a complement), and only
            // those that fit entirely in the remaining space (music card…)
            Item {
                id: notifZone
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.notifs.length > 0
                clip: true
                Column {
                id: notifList
                width: parent.width
                spacing: 2
                Repeater {
                model: panel.notifs.slice(0, 3)

                delegate: Item {
                    id: nt
                    required property var modelData
                    width: notifList.width
                    // hidden if it does not fit entirely (no cut-off notification)
                    readonly property bool tient: y + height <= notifZone.height
                    opacity: tient ? 1 : 0
                    enabled: tient
                    implicitHeight: ntCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                    readonly property bool enReponse: panel.notifReplying === nt.modelData.id

                    HoverHandler { id: ntHover }
                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                        border.width: 1
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: ntHover.hovered || nt.enReponse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Image {   // application icon
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            source: nt.modelData.icon !== "" ? "file://" + nt.modelData.icon : ""
                            sourceSize.width: Kirigami.Units.iconSizes.smallMedium * 2
                            sourceSize.height: Kirigami.Units.iconSizes.smallMedium * 2
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                        ColumnLayout {
                            id: ntCol
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: nt.modelData.app
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                elide: Text.ElideRight
                                text: nt.modelData.title
                                font.weight: Font.DemiBold
                                color: Kirigami.Theme.textColor
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                wrapMode: Text.Wrap
                                maximumLineCount: nt.enReponse ? 8 : 3
                                elide: Text.ElideRight
                                text: nt.modelData.text
                                color: Kirigami.Theme.textColor
                            }
                            PanelButton {   // reply (messaging apps, SMS…)
                                visible: nt.modelData.reply !== "" && !nt.enReponse
                                framed: false
                                text: i18n("Reply")
                                iconName: panel.ico("sms")
                                onClicked: {
                                    panel.notifReplying = nt.modelData.id;
                                    Qt.callLater(function () { ntReponse.forceActiveFocus(); });
                                }
                            }
                            RowLayout {     // reply field
                                Layout.fillWidth: true
                                visible: nt.enReponse
                                PC3.TextField {
                                    id: ntReponse
                                    Layout.fillWidth: true
                                    placeholderText: i18n("Your reply")
                                    onAccepted: if (panel.replyNotif(nt.modelData.id, text)) text = ""
                                    Keys.onEscapePressed: panel.notifReplying = ""
                                }
                                PanelButton {
                                    iconName: panel.ico("send")
                                    implicitWidth: implicitHeight
                                    onClicked: if (panel.replyNotif(nt.modelData.id, ntReponse.text)) ntReponse.text = ""
                                }
                            }
                        }
                        PanelButton {   // dismiss (the message is not deleted)
                            Layout.alignment: Qt.AlignTop
                            framed: false
                            text: "✕"
                            implicitWidth: implicitHeight
                            onClicked: panel.dismissNotif(nt.modelData.id)
                            tip: i18n("Dismiss notification")   // 2.0: tooltip drawn inside the panel (Plasma 6.8 misplaces the tooltips of this window)
                        }
                    }
                }
                }
                }
            }

            // without notification: the free space stays at the bottom
            Item {
                Layout.fillHeight: true
                visible: panel.notifs.length === 0
            }
        }

        // ----- Loading -----
        PC3.BusyIndicator {
            anchors.centerIn: parent
            running: visible
            visible: !panel.loaded
        }

        // ----- Footer strip: same component and same height as the menu's -----
        PlasmaExtras.PlasmoidHeading {
            id: piedVolet
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentHeight: Kirigami.Units.gridUnit * 3 - 10   // same height as the menu's footer
            position: PC3.ToolBar.Footer
            // the strip's background extends to the window edges
            leftInset: -panel.margins.left
            rightInset: -panel.margins.right
            bottomInset: -panel.margins.bottom

            // "···" as in Windows 11: options menu
            PanelButton {
                id: plusBouton
                anchors.right: parent.right
                anchors.rightMargin: Kirigami.Units.gridUnit + panel.recentrageVolet   // Fenestra: panel recentering
                anchors.verticalCenter: parent.verticalCenter
                framed: false
                text: "···"
                implicitWidth: 32    // 1.2: same size as the "···" of Fenestra Search
                implicitHeight: 26
                onClicked: plusMenu.visible = !plusMenu.visible
                tip: i18n("More options")   // 2.0: tooltip drawn inside the panel (Plasma 6.8 misplaces the tooltips of this window)
            }
        }

        // "···" window: same type and layout as the Power window
        PlasmaCore.Dialog {
            id: plusMenu
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true
            visible: false

            // open: the panel and the menu stay open (same principle as Power)
            onVisibleChanged: {
                if (visible) {
                    panel.hold = true;
                    Qt.callLater(plusMenu.reposition);
                } else {
                    panel.hold = false;
                }
            }

            // above the button, aligned on its right edge
            function reposition() {
                var pos = plusBouton.mapToGlobal(plusBouton.width, 0);
                x = Math.round(pos.x - width);
                y = Math.round(pos.y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                spacing: 0
                PlusItem {   // 2.1: direct access to the widget settings
                    label: i18n("Configure Fenestra Menu 11")
                    icone: "settings"
                    onClicked: {
                        plusMenu.visible = false;
                        kicker.expanded = false;
                        kicker.ouvrirReglages();
                    }
                }
                PlusItem {
                    label: i18n("Open KDE Connect")
                    // same icon as the menu's KDE Connect button
                    iconeFichier: Qt.resolvedUrl("../icons/status/fenestra-kdeconnect.svg")
                    onClicked: { plusMenu.visible = false; panel.run("kdeconnect-app"); }
                }
                PlusItem {
                    label: i18n("Hide this panel")
                    icone: "subtract"
                    onClicked: { plusMenu.visible = false; Plasmoid.configuration.kdeConnectPanelOn = false; panel.close(); }
                }
                PlusItem {   // 1.2: "About", like Fenestra Search
                    label: i18n("About Fenestra Menu 11")
                    iconeFichier: "help-about"
                    onClicked: {
                        plusMenu.visible = false;
                        panel.hold = true;        // menu and panel stay open behind it
                        kicker.ouvrirAPropos(panel);
                    }
                }
            }
        }
    }
}
