"""Copies the working files into Interface\\AddOns\\AltsForeverDev, a second copy of the
addon for testing in game next to the installed release.

    python tools/install_dev.py "<WoW>\\_classic_beta_"

The .toc files are renamed to match the folder and titled "Alts Forever (dev)". WoW names
saved data after the folder, so the dev copy keeps its own AltsForeverDev.lua. Enable
only one of the two copies at a time: both use the AltsForeverDB global.
Close the game first if you added a file or changed a .toc; otherwise /reload is enough.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOCS = ["AltsForever.toc", "AltsForever_Camelot.toc"]


def toc_files(text):
    return [line.strip().replace("\\", "/") for line in text.splitlines()
            if line.strip() and not line.startswith("#")]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    addons = os.path.join(sys.argv[1], "Interface", "AddOns")
    if not os.path.isdir(addons):
        sys.exit("install_dev: no Interface/AddOns folder in " + sys.argv[1])
    dev = os.path.join(addons, "AltsForeverDev")
    if os.path.islink(dev) or (os.path.isdir(dev) and os.path.realpath(dev) != os.path.abspath(dev)):
        sys.exit("install_dev: " + dev + " is a link; remove it first")
    os.makedirs(dev, exist_ok=True)

    with open(os.path.join(ROOT, TOCS[0]), encoding="utf-8") as f:
        toc = f.read()
    for name in TOCS:
        target = os.path.join(dev, name.replace("AltsForever", "AltsForeverDev", 1))
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write(toc.replace("## Title: Alts Forever", "## Title: Alts Forever (dev)", 1)
                    .replace("AddOns\\AltsForever\\", "AddOns\\AltsForeverDev\\"))
    files = toc_files(toc) + ["LICENSE", "media/icon.tga", "media/minimap.tga"]
    os.makedirs(os.path.join(dev, "media"), exist_ok=True)
    for name in files:
        shutil.copy2(os.path.join(ROOT, name), os.path.join(dev, name))
    print("copied %d files to %s" % (len(files) + len(TOCS), dev))


if __name__ == "__main__":
    main()
