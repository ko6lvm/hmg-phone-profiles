#!/usr/bin/env python3
"""
Test NEMESIS package specification and label/metadata requirements in NEMESIS.data.
Adheres strictly to NEMESIS v1.1 package specifications (xwtk/hmg_nemesis).
"""

import configparser
import os
import re
import sys
import zipfile

def test_nemesis_data(content, source_label="NEMESIS.data"):
    config = configparser.ConfigParser()
    config.read_string(content)

    print(f"[{source_label}] Verifying NEMESIS metadata...")

    # 1. Section [nemesis]
    assert config.has_section("nemesis"), f"Missing [nemesis] section in {source_label}"
    nemesis = config["nemesis"]

    # version
    version = nemesis.get("version", "")
    assert version in ["1.0", "1.1"], f"Invalid version: {version}"
    print(f"  ✓ Descriptor version: {version}")

    # id
    pkg_id = nemesis.get("id", "")
    assert pkg_id == "hmg-phone-profiles", f"Unexpected package id: {pkg_id}"
    assert len(pkg_id) <= 64, f"id exceeds 64 chars: {len(pkg_id)}"
    assert re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]*$", pkg_id), f"id format invalid: {pkg_id}"
    print(f"  ✓ Package id: {pkg_id}")

    # name
    name = nemesis.get("name", "")
    assert name == "HMG Phone Profiles", f"Unexpected package name: {name}"
    print(f"  ✓ Package name: {name}")

    # author
    author = nemesis.get("author", "")
    assert len(author) > 0, "author is missing or empty"
    assert author == "AutoProfile Team", f"author violates sanitization requirement: {author}"
    print(f"  ✓ Author: {author}")

    # type
    pkg_type = nemesis.get("type", "")
    types = [t.strip() for t in pkg_type.split(",")]
    assert "application" in types and "service" in types, f"type must contain application and service: {pkg_type}"
    print(f"  ✓ Types: {pkg_type}")

    # package-version
    pkg_ver = nemesis.get("package-version", "")
    assert re.match(r"^[0-9]+(\.[0-9]+)*$", pkg_ver), f"package-version must be dotted numbers: {pkg_ver}"
    print(f"  ✓ Package version: {pkg_ver}")

    # short-desc (strictly <= 64 chars, single line)
    short_desc = nemesis.get("short-desc", "")
    assert len(short_desc) > 0, "short-desc is missing"
    assert len(short_desc) <= 64, f"short-desc strictly exceeds 64 chars (len={len(short_desc)}): {short_desc}"
    assert "\n" not in short_desc, "short-desc must be single line"
    print(f"  ✓ short-desc (len={len(short_desc)} <= 64): '{short_desc}'")

    # detailed-desc (strictly <= 256 chars)
    detailed_desc = nemesis.get("detailed-desc", "")
    assert len(detailed_desc) > 0, "detailed-desc is missing"
    assert len(detailed_desc) <= 256, f"detailed-desc strictly exceeds 256 chars (len={len(detailed_desc)}): {detailed_desc}"
    print(f"  ✓ detailed-desc (len={len(detailed_desc)} <= 256): '{detailed_desc}'")

    # os, target-os, models, model, package aliases
    assert nemesis.get("os", "") != "", "os field missing"
    assert nemesis.get("target-os", "") != "", "target-os alias missing"
    assert nemesis.get("models", "") != "", "models field missing"
    assert nemesis.get("model", "") != "", "model alias missing"
    assert nemesis.get("package", "") == "hmg-phone-profiles", "package alias missing or mismatch"
    print(f"  ✓ os / target-os: {nemesis.get('os')} | models / model: {nemesis.get('models')}")

    # hooks
    assert nemesis.get("postinstall") == "scripts/post.sh", f"Invalid postinstall hook: {nemesis.get('postinstall')}"
    assert nemesis.get("preuninstall") == "scripts/preun.sh", f"Invalid preuninstall hook: {nemesis.get('preuninstall')}"
    print("  ✓ postinstall and preuninstall hooks defined correctly")

    # 2. Section [app.0]
    assert config.has_section("app.0"), "Missing [app.0] section"
    app0 = config["app.0"]
    assert app0.get("kind") == "apk", f"app.0 kind must be apk: {app0.get('kind')}"
    assert app0.get("path") == "app/AutoProfile.apk", f"app.0 path invalid: {app0.get('path')}"
    assert app0.get("package") == "hmg.phone.profiles", f"app.0 package invalid: {app0.get('package')}"
    assert app0.get("component") == "hmg.phone.profiles/.MainActivity", f"app.0 component invalid: {app0.get('component')}"
    assert app0.get("uid") == "root", f"app.0 uid invalid: {app0.get('uid')}"
    print("  ✓ [app.0] section valid (kind=apk, entry component=hmg.phone.profiles/.MainActivity)")

    # 3. Section [service.0]
    assert config.has_section("service.0"), "Missing [service.0] section"
    svc0 = config["service.0"]
    assert svc0.get("name") == "hmg-phone-profiles-daemon", f"service.0 name invalid: {svc0.get('name')}"
    assert svc0.get("kind") == "sh", f"service.0 kind invalid: {svc0.get('kind')}"
    assert svc0.get("path") == "svc/helper.sh", f"service.0 path invalid: {svc0.get('path')}"
    assert svc0.get("uid") == "root", f"service.0 uid invalid: {svc0.get('uid')}"
    assert svc0.get("mode") == "restart", f"service.0 mode invalid: {svc0.get('mode')}"
    print("  ✓ [service.0] section valid (name=hmg-phone-profiles-daemon, kind=sh, mode=restart, uid=root)")

    print(f"[{source_label}] ALL NEMESIS SPEC CHECKS PASSED!\n")

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    # Check package/NEMESIS.data
    nemesis_path = os.path.join(repo_root, "package", "NEMESIS.data")
    assert os.path.exists(nemesis_path), f"File not found: {nemesis_path}"
    with open(nemesis_path, "r") as f:
        test_nemesis_data(f.read(), "package/NEMESIS.data")

    # Check zip contents
    zip_path = os.path.join(repo_root, "hmg-phone-profiles.zip")
    if os.path.exists(zip_path):
        with zipfile.ZipFile(zip_path, 'r') as z:
            assert "NEMESIS.data" in z.namelist(), "NEMESIS.data missing from zip root"
            zip_content = z.read("NEMESIS.data").decode("utf-8")
            test_nemesis_data(zip_content, "ZIP hmg-phone-profiles.zip:NEMESIS.data")

if __name__ == "__main__":
    main()
