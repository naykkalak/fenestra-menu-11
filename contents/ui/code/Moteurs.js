/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * SPDX-FileCopyrightText: 2026 naykkalak
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 Web search engines. %s = searched text.
 */
.pragma library

var LISTE = [
    { cle: "duckduckgo", nom: "DuckDuckGo",   adresse: "https://duckduckgo.com/?q=%s" },
    { cle: "google",     nom: "Google",       adresse: "https://www.google.com/search?q=%s" },
    { cle: "bing",       nom: "Bing",         adresse: "https://www.bing.com/search?q=%s" },
    { cle: "qwant",      nom: "Qwant",        adresse: "https://www.qwant.com/?q=%s" },
    { cle: "ecosia",     nom: "Ecosia",       adresse: "https://www.ecosia.org/search?q=%s" },
    { cle: "startpage",  nom: "Startpage",    adresse: "https://www.startpage.com/do/search?q=%s" },
    { cle: "brave",      nom: "Brave Search", adresse: "https://search.brave.com/search?q=%s" }
];

function trouver(cle) {
    for (var i = 0; i < LISTE.length; i++)
        if (LISTE[i].cle === cle) return LISTE[i];
    return null;
}

// output of the moteur-kde.sh script -> { name, address } (DuckDuckGo if nothing readable)
function depuisKde(sortie) {
    var cle = "", nom = "", requete = "";
    String(sortie || "").split("\n").forEach(function(l) {
        if (l.indexOf("Cle=") === 0) cle = l.substring(4).trim();
        else if (l.indexOf("Name=") === 0) nom = l.substring(5).trim();
        else if (l.indexOf("Query=") === 0) requete = l.substring(6).trim();
    });
    var connu = trouver(cle) || trouver(cle.replace(/^(gg|dd|ddg)$/, function(c) {
        return c === "gg" ? "google" : "duckduckgo";
    }));
    if (requete.indexOf("http") === 0) {
        // KDE marks the text placeholder as \\{@} or \{0}...: we replace it with %s
        requete = requete.replace(/\\*\{[^}]*\}/, "%s");
        if (requete.indexOf("%s") !== -1)
            return { nom: nom || (connu ? connu.nom : cle), adresse: requete };
    }
    return connu ? { nom: connu.nom, adresse: connu.adresse } : trouver("duckduckgo");
}

function adresse(moteur, texte) {
    return moteur.adresse.replace("%s", encodeURIComponent(texte));
}

function domaine(moteur) {
    var m = moteur.adresse.match(/^https?:\/\/([^\/?]+)/);
    return m ? m[1].replace(/^www\./, "") : "";
}
