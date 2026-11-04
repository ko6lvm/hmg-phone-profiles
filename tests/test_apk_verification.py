#!/usr/bin/env python3
"""
Test AutoProfile.apk signature, manifest, bytecode, fonts, and assets.
"""

import os
import subprocess
import sys
import zipfile

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    apk_path = os.path.join(repo_root, "package", "app", "AutoProfile.apk")
    assert os.path.exists(apk_path), f"APK not found: {apk_path}"

    sdk_dir = os.environ.get("ANDROID_SDK_ROOT", os.path.expanduser("~/tools/android-sdk"))
    aapt = os.path.join(sdk_dir, "usr", "bin", "aapt")
    apksigner_jar = os.path.join(sdk_dir, "usr", "share", "java", "apksigner-35.0.2.jar")
    ld_path = f"{sdk_dir}/usr/lib:{sdk_dir}/usr/lib/7zip:{sdk_dir}/usr/lib/aarch64-linux-gnu/android"

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = ld_path + ":" + env.get("LD_LIBRARY_PATH", "")

    print("Verifying AutoProfile.apk...")

    # 1. Verify Signature with apksigner
    cmd_verify = ["java", "-jar", apksigner_jar, "verify", "--verbose", apk_path]
    res_verify = subprocess.run(cmd_verify, capture_output=True, text=True)
    assert res_verify.returncode == 0, f"apksigner verify failed: {res_verify.stderr}"
    assert "Verified using v1 scheme (JAR signing): true" in res_verify.stdout
    assert "Verified using v2 scheme (APK Signature Scheme v2): true" in res_verify.stdout
    print("  ✓ APK Signature verified (v1 + v2 schemes valid)")

    # 2. Check AAPT Badging
    cmd_badging = [aapt, "dump", "badging", apk_path]
    res_badging = subprocess.run(cmd_badging, capture_output=True, text=True, env=env)
    assert res_badging.returncode == 0, f"aapt dump badging failed: {res_badging.stderr}"
    badging_out = res_badging.stdout

    assert "package: name='autoprofile.selector'" in badging_out, "Package name mismatch in APK"
    assert "sdkVersion:'19'" in badging_out, "minSdkVersion must be 19 (KitKat 4.4.2)"
    assert "targetSdkVersion:'19'" in badging_out, "targetSdkVersion must be 19"
    assert "launchable-activity: name='autoprofile.selector.MainActivity'" in badging_out, "Launcher activity missing"
    assert "application-label:'Auto Profile Selector'" in badging_out, "App label mismatch"
    print("  ✓ AAPT Badging verified (package: autoprofile.selector, SDK: 19, Activity: MainActivity)")

    # 3. Check Internal Zip Members (fonts, dex, resources)
    with zipfile.ZipFile(apk_path, 'r') as z:
        names = set(z.namelist())
        assert "classes.dex" in names, "classes.dex missing from APK"
        assert "AndroidManifest.xml" in names, "AndroidManifest.xml missing"
        assert "resources.arsc" in names, "resources.arsc missing"
        assert "assets/fonts/HyundaiSans-Regular.ttf" in names, "Hyundai Sans font missing"
        assert "assets/fonts/KiaCube-Regular.ttf" in names, "Kia Cube font missing"
        
        # Check font sizes
        hyundai_info = z.getinfo("assets/fonts/HyundaiSans-Regular.ttf")
        assert hyundai_info.file_size > 1_000_000, "Hyundai Sans font truncated"
        kia_info = z.getinfo("assets/fonts/KiaCube-Regular.ttf")
        assert kia_info.file_size > 1_000_000, "Kia Cube font truncated"

        print(f"  ✓ Fonts verified: Hyundai Sans ({hyundai_info.file_size} B), Kia Cube ({kia_info.file_size} B)")
        print(f"  ✓ Dex verified: classes.dex ({z.getinfo('classes.dex').file_size} B)")

    print("ALL APK VERIFICATION CHECKS PASSED!\n")

if __name__ == "__main__":
    main()
