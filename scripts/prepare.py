#!/usr/bin/env python3
"""Fetch the pinned Telegram-iOS tree and apply the reviewed source patch."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PROJECT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((PROJECT / "manifest.json").read_text(encoding="utf-8"))


def run(*args, cwd=None, capture=False):
    return subprocess.run(args, cwd=cwd, check=True,
                          capture_output=capture, text=True)


def prepare(source: Path, fetch_submodules=False):
    patch = PROJECT / MANIFEST["patch"]["path"]
    if hashlib.sha256(patch.read_bytes()).hexdigest() != MANIFEST["patch"]["sha256"]:
        raise RuntimeError("Patch integrity mismatch; review the modified patch before updating its hash.")
    source = source.resolve()
    if not source.exists():
        source.mkdir(parents=True)
        run("git", "init", str(source))
        run("git", "-C", str(source), "remote", "add", "origin", MANIFEST["upstream"]["url"])
        run("git", "-C", str(source), "fetch", "--depth=1", "origin", MANIFEST["upstream"]["commit"])
        run("git", "-C", str(source), "-c", "core.longpaths=true", "checkout", "--detach", "FETCH_HEAD")
    elif not (source / ".git").exists():
        raise RuntimeError("Existing source directory is not a Git checkout; it will not be overwritten.")
    revision = run("git", "rev-parse", "HEAD", cwd=source, capture=True).stdout.strip()
    if revision != MANIFEST["upstream"]["commit"]:
        raise RuntimeError(f"Wrong upstream revision: {revision}. Use a new source directory.")
    check = subprocess.run(["git", "apply", "--check", str(patch)], cwd=source, capture_output=True, text=True)
    if check.returncode == 0:
        run("git", "apply", str(patch), cwd=source)
        print("Applied PatchClient source changes.")
    else:
        reverse = subprocess.run(["git", "apply", "--reverse", "--check", str(patch)], cwd=source,
                                 capture_output=True, text=True)
        if reverse.returncode != 0:
            raise RuntimeError("Source differs from both the original and patched tree:\n" + check.stderr)
        print("PatchClient changes are already present.")
    if fetch_submodules:
        run("git", "submodule", "update", "--init", "--recursive", "--depth=1", "-j4", cwd=source)
    return source


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=PROJECT / "work" / "telegram-ios")
    parser.add_argument("--fetch-submodules", action="store_true")
    args = parser.parse_args()
    prepare(args.source, args.fetch_submodules)
