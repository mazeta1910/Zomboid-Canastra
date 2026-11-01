"""Runs the mod's Lua code outside the game (Lua 5.1, like Kahlua).

  1. syntax check of every Lua file
  2. translation files: valid JSON and same keys in every language
  3. rules engine + bot simulations (shared code only)
  4. singleplayer integration through server, client and UI windows (PZ API mocked)

Usage: python tests/run_tests.py    (requires: pip install lupa)
"""
import glob
import json
import os
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Contents", "mods", "Canastra", "42", "media")
LUA = os.path.join(MEDIA, "lua")
TRANSLATE = os.path.join(LUA, "shared", "Translate")
TESTS = os.path.join(ROOT, "tests")


def posix(p):
    return p.replace("\\", "/")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def check_syntax():
    lua = lua51.LuaRuntime()
    compile_ = lua.eval("function(src, name) local f, err = loadstring(src, name) return err end")
    errors = 0
    for path in glob.glob(os.path.join(LUA, "**", "*.lua"), recursive=True):
        err = compile_(read(path), os.path.relpath(path, ROOT))
        if err:
            print("SYNTAX:", err)
            errors += 1
    return errors


def load_translations():
    errors = 0
    langs = {}
    for lang_dir in glob.glob(os.path.join(TRANSLATE, "*")):
        lang = os.path.basename(lang_dir)
        keys = {}
        for path in glob.glob(os.path.join(lang_dir, "*.json")):
            prefix = {"IG_UI": "IGUI_", "ContextMenu": "ContextMenu_", "Sandbox": "Sandbox_", "Tooltip": "Tooltip_"}.get(
                os.path.splitext(os.path.basename(path))[0], "")
            try:
                data = json.loads(read(path))
            except ValueError as e:
                print("JSON:", path, e)
                errors += 1
                continue
            for k, v in data.items():
                if prefix and not k.startswith(prefix):
                    print("PREFIX: %s in %s" % (k, path))
                    errors += 1
                keys[k] = v
        langs[lang] = keys
    base = langs.get("EN", {})
    for lang, keys in langs.items():
        for k in sorted(set(base) - set(keys)):
            print("MISSING in %s: %s" % (lang, k))
            errors += 1
        for k in sorted(set(keys) - set(base)):
            print("EXTRA in %s: %s" % (lang, k))
            errors += 1
    return errors, base


def run_lua(test_file, translations=None):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    dirs = [posix(os.path.join(LUA, d)) for d in ("shared", "client", "server")]
    g.SHARED_DIR = dirs[0]
    g.LUA_DIRS = lua.table_from(dirs)
    g.MEDIA_DIR = posix(MEDIA)
    g.TRANSLATIONS = lua.table_from(translations or {})
    lua.execute(read(os.path.join(TESTS, "bootstrap.lua")))
    if translations is not None:
        lua.execute(read(os.path.join(TESTS, "pz_mocks.lua")))
    return lua.execute(read(os.path.join(TESTS, test_file))) or 0


def main():
    failures = check_syntax()
    terr, en = load_translations()
    failures += terr
    print("Engine tests", flush=True)
    failures += run_lua("test_engine.lua")
    print("UI tests", flush=True)
    failures += run_lua("test_ui.lua", en)
    print("\nTOTAL FAILURES:", failures)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
