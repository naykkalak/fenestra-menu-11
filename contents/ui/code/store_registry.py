#!/usr/bin/env python3
# Fenestra Menu 11: record the component in the KDE Store list of installed add-ons,
# so that Discover can offer its updates (also when it was installed by hand).
# Part of the Fenestra series by naykkalak - https://github.com/naykkalak/fenestra-menu-11
# Copyright (C) naykkalak (2026) for Fenestra Menu 11
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   store_registry.py add      add the entry, or refresh its version (nothing is written if it is up to date)
#   store_registry.py remove   remove the entry
#
# The list is ~/.local/share/knewstuff3/plasmoids.knsregistry (an XML file written by KDE).
# An entry made by the KDE Store itself is never replaced, only its version is refreshed.
# Only the copy installed for the current user is recorded.
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

STORE_ID = "2379358"          # page of Fenestra Menu 11 on store.kde.org
CATEGORY = "706"              # "Plasma 6 widgets" category of the KDE Store
NAME = "Fenestra Menu 11"
AUTHOR = "naykkalak"
REGISTRY = os.path.expanduser("~/.local/share/knewstuff3/plasmoids.knsregistry")
INSTALLED = os.path.expanduser("~/.local/share/plasma/plasmoids/org.fenestra.menu11")
FOLDER = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))))
END = "</hotnewstuffregistry>"
SKELETON = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE khotnewstuff3>\n'
            '<hotnewstuffregistry>\n' + END + '\n')
BLOCK = re.compile(r"[ \t]*<stuff\b.*?</stuff>[ \t]*\n?", re.S)


def read():
    if os.path.isfile(REGISTRY):
        with open(REGISTRY, encoding="utf-8") as f:
            return f.read()
    return SKELETON


def write(text):
    ET.fromstring(text.encode("utf-8"))          # never write a broken file
    os.makedirs(os.path.dirname(REGISTRY), exist_ok=True)
    tmp = REGISTRY + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, REGISTRY)


def mine(block):
    return "<id>%s</id>" % STORE_ID in block


def add():
    if os.path.realpath(FOLDER) != os.path.realpath(INSTALLED):
        return                                    # not the copy installed for this user
    with open(os.path.join(FOLDER, "metadata.json"), encoding="utf-8") as f:
        version = json.load(f)["KPlugin"]["Version"]
    text = read()
    if text.count(END) != 1:
        raise SystemExit("unexpected registry format")
    for m in BLOCK.finditer(text):
        if mine(m.group(0)):                      # already there: refresh the version only
            new = re.sub(r"<version>.*?</version>", "<version>%s</version>" % escape(version),
                         m.group(0), count=1, flags=re.S)
            if new != m.group(0):
                write(text[:m.start()] + new + text[m.end():])
            return
    entry = (' <stuff category="%s">\n  <name>%s</name>\n  <providerid>api.kde-look.org</providerid>\n'
             '  <author>%s</author>\n  <homepage>https://store.kde.org/p/%s</homepage>\n'
             '  <licence></licence>\n  <version>%s</version>\n  <installedfile>%s/</installedfile>\n'
             '  <id>%s</id>\n  <status>installed</status>\n </stuff>\n'
             % (CATEGORY, escape(NAME), AUTHOR, STORE_ID, escape(version),
                escape(INSTALLED.rstrip("/")), STORE_ID))
    write(text.replace(END, entry + END))


def remove():
    if not os.path.isfile(REGISTRY):
        return
    text = read()
    out = BLOCK.sub(lambda m: "" if mine(m.group(0)) else m.group(0), text)
    if out != text:
        write(out)


if __name__ == "__main__":
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "add":
            add()
        elif len(sys.argv) == 2 and sys.argv[1] == "remove":
            remove()
        else:
            raise SystemExit(__doc__)
    except SystemExit:
        raise
    except Exception as error:                    # never block anything for this
        print("store list not updated: %s" % error, file=sys.stderr)
        sys.exit(1)
