#!/usr/bin/env python3
"""Compile and test the actual policy against the pinned Telegram API types."""
from pathlib import Path
import shutil
import subprocess

from prepare import PROJECT, prepare

if __name__ == "__main__":
    source = prepare(PROJECT / "work" / "telegram-ios")
    package = PROJECT / "work" / "policy-tests"
    api_target = package / "Sources" / "TelegramApi"
    policy_target = package / "Sources" / "PatchClientCore"
    tests_target = package / "Tests" / "PatchClientCoreTests"
    for directory in [api_target, policy_target, tests_target]:
        directory.mkdir(parents=True, exist_ok=True)
    for api_source in (source / "submodules" / "TelegramApi" / "Sources").glob("*.swift"):
        shutil.copy2(api_source, api_target / api_source.name)
    for name in ["PatchClientPolicy", "PatchClientStorage", "FaithgramPreferences", "FaithgramVault", "FaithgramHistoryStore", "FaithgramSessionBackup", "FaithgramMessageFilter", "FaithgramMediaArchive"]:
        shutil.copy2(source / f"submodules/TelegramCore/Sources/PatchClient/{name}.swift", policy_target / f"{name}.swift")
    shutil.copy2(source / "submodules/TelegramCore/Sources/SyncCore/SyncCore_AccountBackupDataAttribute.swift", policy_target / "AccountBackupData.swift")
    for test_source in (PROJECT / "tests").glob("*Tests.swift"):
        shutil.copy2(test_source, tests_target / test_source.name)
    shutil.copy2(PROJECT / "tests/Package.swift", package / "Package.swift")
    subprocess.run(["swift", "test", "--jobs", "2"], cwd=package, check=True)

    from interface_tests import run as run_interface_tests
    run_interface_tests(source, PROJECT / "work" / "interface-tests")
