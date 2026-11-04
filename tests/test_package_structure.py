#!/usr/bin/env python3
"""
Test NEMESIS package archive structure and file integrity.
"""

import os
import sys
import zipfile

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    zip_path = os.path.join(repo_root, "autoprofile.selector.zip")
    assert os.path.exists(zip_path), f"Package zip not found: {zip_path}"

    expected_files = {
        "NEMESIS.data",
        "app/AutoProfile.apk",
        "svc/helper.sh",
        "scripts/post.sh",
        "scripts/preun.sh",
    }

    print("Verifying NEMESIS package structure in autoprofile.selector.zip...")
    with zipfile.ZipFile(zip_path, 'r') as z:
        names = set(z.namelist())
        for f in expected_files:
            assert f in names, f"Required file missing from package: {f}"
            info = z.getinfo(f)
            assert info.file_size > 0, f"File {f} is empty!"
            print(f"  ✓ Found {f} ({info.file_size} bytes)")

        # Verify no directory traversal / zip slip
        for name in names:
            assert ".." not in name and not name.startswith("/"), f"Illegal path in package: {name}"

        # Verify APK is non-trivial (>100KB)
        apk_info = z.getinfo("app/AutoProfile.apk")
        assert apk_info.file_size > 100_000, f"APK suspiciously small: {apk_info.file_size} bytes"

    # Verify USB installer ZIP if present
    usb_zip_path = os.path.join(repo_root, "autoprofile.selector-usb.zip")
    if os.path.exists(usb_zip_path):
        print("Verifying USB installer structure in autoprofile.selector-usb.zip...")
        with zipfile.ZipFile(usb_zip_path, 'r') as uz:
            unames = set(uz.namelist())
            assert "NEMESIS.data" in unames, "USB installer missing root NEMESIS.data"
            assert "packages/autoprofile.selector.zip" in unames, "USB installer missing packages/autoprofile.selector.zip"
            # Read root descriptor
            desc = uz.read("NEMESIS.data").decode("utf-8")
            assert "type=install" in desc, f"USB root NEMESIS.data must be type=install, got:\n{desc}"
            assert "path=packages/autoprofile.selector.zip" in desc, f"USB root NEMESIS.data invalid path:\n{desc}"
            print("  ✓ Found USB trigger NEMESIS.data (type=install)")
            print("  ✓ Found payload packages/autoprofile.selector.zip")

    # Also verify local package folder permissions
    scripts = [
        os.path.join(repo_root, "package", "svc", "helper.sh"),
        os.path.join(repo_root, "package", "scripts", "post.sh"),
        os.path.join(repo_root, "package", "scripts", "preun.sh"),
    ]
    for s in scripts:
        assert os.path.exists(s), f"Script not found: {s}"
        assert os.access(s, os.X_OK), f"Script not executable: {s}"
        print(f"  ✓ Script executable: {os.path.relpath(s, repo_root)}")

    print("ALL PACKAGE STRUCTURE CHECKS PASSED!\n")

if __name__ == "__main__":
    main()
