#!/usr/bin/env python3
"""Compile and test the actual policy against the pinned Telegram API types."""
from pathlib import Path
import json
import shutil
import subprocess

from prepare import PROJECT, prepare

def copy_if_changed(source, destination):
    if not destination.exists() or source.read_bytes() != destination.read_bytes():
        shutil.copy2(source, destination)


if __name__ == "__main__":
    source = prepare(PROJECT / "work" / "telegram-ios")
    manifest = json.loads((PROJECT / "manifest.json").read_text(encoding="utf-8"))
    sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], check=True, capture_output=True, text=True).stdout.strip()
    syntax_failures = []
    swift_files = [path for path in manifest["patch"]["files"] if path.endswith(".swift")]
    for path in swift_files:
        result = subprocess.run(["xcrun", "swiftc", "-frontend", "-parse", "-target", "arm64-apple-ios13.0", "-sdk", sdk, str(source / path)], capture_output=True, text=True, timeout=90)
        if result.returncode:
            print(result.stderr, flush=True)
            syntax_failures.append(path)
    if syntax_failures:
        raise RuntimeError("Swift syntax check failed: " + ", ".join(syntax_failures))
    print(f"Swift syntax passed for {len(swift_files)} modified source files.", flush=True)
    package = PROJECT / "work" / "policy-tests"
    api_target = package / "Sources" / "TelegramApi"
    policy_target = package / "Sources" / "PatchClientCore"
    tests_target = package / "Tests" / "PatchClientCoreTests"
    for directory in [api_target, policy_target, tests_target]:
        directory.mkdir(parents=True, exist_ok=True)
    for api_source in (source / "submodules" / "TelegramApi" / "Sources").glob("*.swift"):
        copy_if_changed(api_source, api_target / api_source.name)
    for name in ["PatchClientPolicy", "PatchClientStorage", "FaithgramPreferences", "FaithgramVault", "FaithgramHistoryStore", "FaithgramSessionBackup", "FaithgramMessageFilter", "FaithgramMediaArchive", "FaithgramVisualPreferences", "FaithgramProtocolLog"]:
        copy_if_changed(source / f"submodules/TelegramCore/Sources/PatchClient/{name}.swift", policy_target / f"{name}.swift")
    copy_if_changed(source / "submodules/TelegramCore/Sources/SyncCore/SyncCore_AccountBackupDataAttribute.swift", policy_target / "AccountBackupData.swift")
    for test_source in (PROJECT / "tests").glob("*Tests.swift"):
        copy_if_changed(test_source, tests_target / test_source.name)
    copy_if_changed(PROJECT / "tests/Package.swift", package / "Package.swift")
    subprocess.run(["swift", "test", "--jobs", "2", "-Xswiftc", "-Xfrontend", "-Xswiftc", "-warn-long-function-bodies=500", "-Xswiftc", "-Xfrontend", "-Xswiftc", "-warn-long-expression-type-checking=200"], cwd=package, check=True, timeout=900)

    from interface_tests import run as run_interface_tests
    run_interface_tests(source, PROJECT / "work" / "interface-tests")
