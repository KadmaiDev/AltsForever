"""Builds the Alts Forever release zip and, with --upload, sends it to CurseForge.

    python tools/release.py                         build dist/AltsForever-<version>.zip
    python tools/release.py --upload CHANGELOG.md   build, then upload as a beta file

Runs the tests first with `luajit` (or the LUAJIT environment variable).

The zip holds one AltsForever/ folder with only the files the game loads (the .toc
files and the .lua files they list) plus LICENSE. Anything else stops the build.
The CurseForge token comes from the CURSE_API_KEY environment variable (or the
Windows user environment) and is never printed.
"""
import json
import os
import subprocess
import sys
import uuid
import zipfile
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOCS = ["AltsForever.toc", "AltsForever_Camelot.toc"]
EXTRA = ["LICENSE"]
ALLOWED = (".toc", ".lua")

PROJECT_ID = 1709551
API = "https://wow.curseforge.com/api"
GAME_VERSIONS = [17053]  # WoW Forever 1.60.1
RELEASE_TYPE = "beta"


def fail(msg):
    sys.exit("release: " + msg)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def toc_files(toc):
    files = []
    for line in read(toc).splitlines():
        line = line.strip()
        # SavedData\ is the player's own folder link, never shipped.
        if line and not line.startswith("#") and not line.startswith("SavedData"):
            files.append(line.replace("\\", "/"))
    return files


def version():
    for line in read(TOCS[0]).splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    fail("no ## Version in " + TOCS[0])


def build():
    if read(TOCS[0]) != read(TOCS[1]):
        fail("the two .toc files differ")
    tests = subprocess.run([os.environ.get("LUAJIT", "luajit"), "tests/run.lua"], cwd=ROOT, capture_output=True, text=True)
    if tests.returncode != 0:
        fail("tests failed:\n" + tests.stdout[-2000:])

    files = TOCS + toc_files(TOCS[0]) + EXTRA
    for f in files:
        if f not in EXTRA and not f.endswith(ALLOWED):
            fail("refusing to ship " + f)
        if not os.path.isfile(os.path.join(ROOT, f)):
            fail("missing " + f)

    ver = version()
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    path = os.path.join(ROOT, "dist", "AltsForever-%s.zip" % ver)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(os.path.join(ROOT, f), "AltsForever/" + f)
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    print("built %s (%d files):" % (os.path.relpath(path, ROOT), len(names)))
    for n in names:
        print("  " + n)
    return path, ver


def token():
    key = os.environ.get("CURSE_API_KEY")
    if not key and sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
                key = winreg.QueryValueEx(k, "CURSE_API_KEY")[0]
        except OSError:
            key = None
    if not key:
        fail("CURSE_API_KEY is not set")
    return key


def upload(path, ver, changelog_path):
    changelog = open(changelog_path, encoding="utf-8").read()
    metadata = {
        "changelog": changelog,
        "changelogType": "markdown",
        "displayName": "Alts Forever " + ver,
        "gameVersions": GAME_VERSIONS,
        "releaseType": RELEASE_TYPE,
    }
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        data = f.read()
    body = b"".join([
        ("--%s\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
         "Content-Type: application/json\r\n\r\n" % boundary).encode(),
        json.dumps(metadata).encode(), b"\r\n",
        ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
         "Content-Type: application/zip\r\n\r\n" % (boundary, os.path.basename(path))).encode(),
        data, b"\r\n",
        ("--%s--\r\n" % boundary).encode(),
    ])
    req = urllib.request.Request(
        "%s/projects/%d/upload-file" % (API, PROJECT_ID), data=body, method="POST",
        headers={"X-Api-Token": token(), "Content-Type": "multipart/form-data; boundary=" + boundary})
    try:
        with urllib.request.urlopen(req) as r:
            print("uploaded: HTTP %d %s" % (r.status, r.read().decode()))
    except urllib.error.HTTPError as e:
        fail("upload failed: HTTP %d %s" % (e.code, e.read().decode()[:1000]))


if __name__ == "__main__":
    path, ver = build()
    if len(sys.argv) >= 2 and sys.argv[1] == "--upload":
        if len(sys.argv) < 3:
            fail("--upload needs a changelog file")
        upload(path, ver, sys.argv[2])
