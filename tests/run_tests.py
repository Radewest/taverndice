"""Run Tjommie's tests: Lua syntax check (luaparser) + smoke tests in an embedded Lua (lupa).

    pip install lupa luaparser
    python3 tests/run_tests.py
"""
import glob
import os
import sys

from lupa import LuaRuntime
from luaparser import ast

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def syntax_check():
    bad = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "*.lua"))):
        try:
            ast.parse(open(path, encoding="utf-8").read())
        except Exception as e:  # noqa: BLE001
            print(f"SYNTAX ERROR {os.path.basename(path)}: {e}")
            bad += 1
    print(f"Syntax check: {bad} file(s) with errors")
    return bad == 0


def smoke():
    lua = LuaRuntime()
    lua.globals().arg = lua.table(ROOT.replace("\\", "/"))
    lua.globals().arg[1] = ROOT.replace("\\", "/")
    try:
        lua.execute(f'dofile("{ROOT}/tests/smoke.lua")'.replace("\\", "/"))
        return True
    except Exception as e:  # noqa: BLE001
        print(f"Smoke tests failed: {e}")
        return False


if __name__ == "__main__":
    ok = syntax_check() and smoke()
    sys.exit(0 if ok else 1)
