#!/usr/bin/env python3
"""Regenerate the source patch from the prepared tree and refresh the manifest and source mirror."""
import hashlib
import json
import pathlib
import shutil
import subprocess

PROJECT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "work" / "telegram-ios"
MANIFEST = PROJECT / "manifest.json"
PATCH = PROJECT / "patches" / "0001-local-policy.patch"
MIRRORED = ["submodules/TelegramCore/Sources/PatchClient", "submodules/SettingsUI/Sources"]


def git(*args):
    return subprocess.run(["git", "-C", str(SOURCE), *args], check=True, capture_output=True, text=True).stdout


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = {destination for asset in manifest["assets"] for destination in asset["destinations"]}
    untracked = [line[3:] for line in git("status", "--short", "--untracked-files=all").splitlines() if line.startswith("??")]
    for path in untracked:
        if path not in assets and not path.endswith(".DS_Store"):
            git("add", "-N", path)
    excludes = [f":(exclude){destination}" for destination in assets]
    patch = git("diff", "HEAD", "--", ".", *excludes)
    if not patch.startswith("diff --git"):
        raise SystemExit("no changes against the pinned revision")
    PATCH.write_text(patch, encoding="utf-8")
    files = sorted(git("diff", "--name-only", "HEAD", "--", ".", *excludes).splitlines())
    manifest["patch"]["sha256"] = hashlib.sha256(patch.encode("utf-8")).hexdigest()
    manifest["patch"]["files"] = files
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    mirrored = []
    for path in files:
        if path.endswith(".swift") and any(path.startswith(prefix + "/") for prefix in MIRRORED):
            name = pathlib.Path(path).name
            if (PROJECT / "source" / name).exists() or path.startswith(MIRRORED[0] + "/") or name.startswith("Faithgram") or name.startswith("PatchClient"):
                shutil.copyfile(SOURCE / path, PROJECT / "source" / name)
                mirrored.append(name)
    subprocess.run(["git", "-C", str(SOURCE), "apply", "--reverse", "--check", str(PATCH)], check=True)
    print(f"patch lines: {len(patch.splitlines())} files: {len(files)} mirrored: {len(mirrored)} sha256: {manifest['patch']['sha256']}")


if __name__ == "__main__":
    main()
