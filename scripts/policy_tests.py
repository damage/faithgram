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
    shutil.copy2(source / "submodules/TelegramCore/Sources/PatchClient/PatchClientPolicy.swift",
                 policy_target / "PatchClientPolicy.swift")
    shutil.copy2(PROJECT / "tests/PolicyTests.swift", tests_target / "PolicyTests.swift")
    shutil.copy2(PROJECT / "tests/Package.swift", package / "Package.swift")
    subprocess.run(["swift", "test", "--jobs", "2"], cwd=package, check=True)
