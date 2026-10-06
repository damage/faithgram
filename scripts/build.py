#!/usr/bin/env python3
"""Build an unsigned device IPA on macOS for subsequent personal signing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import zipfile

from prepare import PROJECT, prepare


def configuration_from_environment():
    api_id = os.environ.get("TELEGRAM_API_ID", "")
    api_hash = os.environ.get("TELEGRAM_API_HASH", "")
    bundle_id = os.environ.get("FAITHGRAM_BUNDLE_ID", "org.personal.faithgram")
    if not api_id.isdecimal() or int(api_id) <= 0:
        raise RuntimeError("Set TELEGRAM_API_ID to your own Telegram application ID.")
    if not re.fullmatch(r"[0-9a-fA-F]{32}", api_hash):
        raise RuntimeError("Set TELEGRAM_API_HASH to your own 32-character application hash.")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", bundle_id):
        raise RuntimeError("Invalid bundle ID.")
    return {
        "bundle_id": bundle_id,
        "api_id": api_id,
        "api_hash": api_hash,
        "team_id": "0000000000",
        "app_center_id": "0",
        "is_internal_build": "false",
        "is_appstore_build": "false",
        "appstore_id": "0",
        "app_specific_url_scheme": "faithgram",
        "premium_iap_product_id": "",
        "enable_siri": False,
        "enable_icloud": False,
    }


def build(source: Path, build_number: int):
    if platform.system() != "Darwin":
        raise RuntimeError("The native iOS build requires macOS with Xcode. Run the prepared cloud workflow.")
    configuration = configuration_from_environment()
    source = prepare(source, fetch_submodules=True)
    versions = json.loads((source / "versions.json").read_text())
    required = versions["xcode"]
    actual = subprocess.run(["xcodebuild", "-version"], check=True, capture_output=True, text=True).stdout
    if f"Xcode {required}\n" not in actual:
        raise RuntimeError(f"This pinned source requires Xcode {required}. Select that installation first.")
    build_input = source / "build-input" / "faithgram-configuration.json"
    build_input.parent.mkdir(parents=True, exist_ok=True)
    build_input.write_text(json.dumps(configuration), encoding="utf-8")
    build_input.chmod(0o600)
    artifacts = PROJECT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    flags = " ".join([
        "--//Telegram:disableProvisioningProfiles",
        "--//Telegram:disableExtensions",
        "--features=disable_legacy_signing",
    ])
    command = [
        sys.executable, "build-system/Make/Make.py",
        f"--cacheDir={PROJECT / 'work' / 'bazel-cache'}",
        "build", f"--configurationPath={build_input}",
        "--xcodeManagedCodesigning", f"--buildNumber={build_number}",
        "--configuration=release_arm64", f"--outputBuildArtifactsPath={artifacts}",
    ]
    # This upstream revision accepts --bazelArguments but does not forward it.
    bazelrc = source / ".bazelrc"
    original_bazelrc = bazelrc.read_bytes()
    ios_rules = source / "build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl"
    original_rules = ios_rules.read_bytes()
    normalized_rules = original_rules.replace(b"\r\n", b"\n")
    if hashlib.sha256(normalized_rules).hexdigest() != "900fe828aa2d5f9ac236aec3555cf4f01944a012273ea03a12f9b52e8b601540":
        build_input.unlink(missing_ok=True)
        raise RuntimeError("The pinned iOS build rules have changed.")
    profile_partial = b"    if platform_prerequisites.platform.is_device:\n        processor_partials.append(\n            partials.provisioning_profile_partial("
    unsigned_partial = profile_partial.replace(b".is_device:", b'.is_device and "disable_legacy_signing" not in features:')
    try:
        bazelrc.write_bytes(original_bazelrc + f"\nbuild {flags}\n".encode("utf-8"))
        # Match profile embedding to the pinned rules' existing signing feature.
        ios_rules.write_bytes(normalized_rules.replace(profile_partial, unsigned_partial))
        subprocess.run(command, cwd=source, check=True)
    finally:
        ios_rules.write_bytes(original_rules)
        bazelrc.write_bytes(original_bazelrc)
        build_input.unlink(missing_ok=True)
    ipa = artifacts / "Telegram.ipa"
    if not ipa.exists():
        raise RuntimeError("The build did not produce an IPA.")
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        if not any(name.startswith("Payload/") and name.endswith(".app/Telegram") for name in names):
            raise RuntimeError("The artifact does not contain the expected iPhone app binary.")
        if any(name.endswith("embedded.mobileprovision") for name in names):
            raise RuntimeError("Unexpected provisioning profile in the unsigned artifact.")
    destination = artifacts / "Faithgram-unsigned.ipa"
    ipa.replace(destination)
    print(f"Created {destination}. Sign this IPA locally before installing it.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=PROJECT / "work" / "telegram-ios")
    parser.add_argument("--build-number", type=int, default=1)
    args = parser.parse_args()
    build(args.source, args.build_number)
