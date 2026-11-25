"""Writes CIB element changes in one update: copy the live CIB, edit the copy (CIB_file), crm_diff, one
cibadmin --patch. A patch refused because the CIB moved since the copy reruns the whole sequence on a fresh copy.

Argument: JSON {changes: [{action, scope, xpath, xml}], retries, delay, stale_rc, hook}. Exit 0 written,
3 the CIB changed on every attempt, 1 any other error (stderr says which command).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time


def run(argv, env=None):
    return subprocess.run(argv, capture_output=True, text=True, env=env, check=False)


def fail(what, res):
    sys.stderr.write("%s failed (rc %d): %s%s" % (what, res.returncode, res.stderr, res.stdout))
    sys.exit(1)


def attempt(work, changes, hook):
    original, new, patch = (os.path.join(work, n) for n in ("original.xml", "new.xml", "patch.xml"))
    res = run(["cibadmin", "--query"])
    if res.returncode != 0:
        fail("cibadmin --query", res)
    with open(original, "w", encoding="utf-8") as f:
        f.write(res.stdout)
    shutil.copyfile(original, new)
    env = dict(os.environ, CIB_file=new)
    for c in changes:
        if c["action"] == "create":
            argv = ["cibadmin", "--create", "--scope", c["scope"], "--xml-text", c["xml"]]
        else:
            argv = ["cibadmin", "--replace", "--xpath", c["xpath"], "--xml-text", c["xml"]]
        res = run(argv, env)
        if res.returncode != 0:
            fail(" ".join(argv[:2]) + " on the copy", res)
    # crm_diff exits 1 when the files differ
    res = run(["crm_diff", "--original", original, "--new", new])
    if res.returncode != 1 or not res.stdout:
        fail("crm_diff", res)
    with open(patch, "w", encoding="utf-8") as f:
        f.write(res.stdout)
    if hook:
        res = run(["/bin/sh", "-c", hook])
        if res.returncode != 0:
            fail("the test hook", res)
    return run(["cibadmin", "--patch", "--xml-file", patch])


def main():
    args = json.loads(sys.argv[1])
    for n in range(args["retries"] + 1):
        work = tempfile.mkdtemp(suffix=".cib")
        try:
            # The hook (tests only) changes the live CIB between copy and patch, on the first attempt only
            res = attempt(work, args["changes"], args.get("hook") if n == 0 else "")
        finally:
            shutil.rmtree(work, ignore_errors=True)
        if res.returncode == 0:
            print("written on attempt %d" % (n + 1))
            return
        if res.returncode not in args["stale_rc"]:
            fail("cibadmin --patch", res)
        sys.stderr.write("attempt %d: the CIB changed since the copy: %s" % (n + 1, res.stderr))
        if n < args["retries"]:
            time.sleep(args["delay"])
    sys.exit(3)


main()
