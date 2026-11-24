#!/bin/sh
# SPDX-FileCopyrightText: 2026 naykkalak
# SPDX-License-Identifier: GPL-3.0-or-later
# Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
# Web search engine chosen in KDE
# (System Settings > Web Search Keywords): prints Cle=, Name= and Query=
cle=$(kreadconfig6 --file kuriikwsfilterrc --group General --key DefaultWebShortcut 2>/dev/null)
[ -z "$cle" ] && cle=duckduckgo
echo "Cle=$cle"
for d in "$HOME/.local/share/kf6/searchproviders" /usr/share/kf6/searchproviders /usr/local/share/kf6/searchproviders; do
    if [ -f "$d/$cle.desktop" ]; then
        grep -E '^(Name|Query)=' "$d/$cle.desktop"
        break
    fi
done
