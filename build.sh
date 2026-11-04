#!/usr/bin/env bash
# ==============================================================================
# build.sh — Standalone NEMESIS Package & Android APK Build System
# Target: 2024 Hyundai Ioniq 5 Limited (Gen5W, Android 4.4.2 KitKat / API 19)
# Package: autoprofile.selector
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================================================"
echo " Building NEMESIS Package: autoprofile.selector"
echo " Target: Gen5W / Android 4.4.2 KitKat (API 19) / Firmware 260507"
echo "======================================================================"

# Toolchain configuration
SDK_DIR="${ANDROID_SDK_ROOT:-$HOME/tools/android-sdk}"
AAPT="$SDK_DIR/usr/bin/aapt"
ZIPALIGN="$SDK_DIR/usr/bin/zipalign"
DX_JAR="$SDK_DIR/usr/share/java/com.android.dx-10.0.0.jar"
APKSIGNER_JAR="$SDK_DIR/usr/share/java/apksigner-35.0.2.jar"
ANDROID_JAR="$SDK_DIR/usr/share/java/com.android.android-23.jar"
ZIP_BIN="$SDK_DIR/usr/bin/zip"
UNZIP_BIN="$SDK_DIR/usr/bin/unzip"

export LD_LIBRARY_PATH="$SDK_DIR/usr/lib:$SDK_DIR/usr/lib/7zip:$SDK_DIR/usr/lib/aarch64-linux-gnu/android:${LD_LIBRARY_PATH:-}"

# Check prerequisites
for tool in "$AAPT" "$ZIPALIGN" "$DX_JAR" "$APKSIGNER_JAR" "$ANDROID_JAR" "$ZIP_BIN"; do
    if [ ! -e "$tool" ]; then
        echo "[ERROR] Missing required tool/library: $tool" >&2
        exit 1
    fi
done

# Prepare build directories
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUILD="$BUILD_DIR/app"
GEN_DIR="$APP_BUILD/gen"
CLASSES_DIR="$APP_BUILD/classes"
KEYSTORE_DIR="$BUILD_DIR/keystore"

rm -rf "$APP_BUILD"
mkdir -p "$GEN_DIR" "$CLASSES_DIR" "$KEYSTORE_DIR" "package/app" "package/svc" "package/scripts"

# ------------------------------------------------------------------------------
# 1. Generate R.java via AAPT
# ------------------------------------------------------------------------------
echo ">>> [1/7] Generating R.java from resources..."
"$AAPT" package -f -m \
    -J "$GEN_DIR" \
    -M "$SCRIPT_DIR/app/src/main/AndroidManifest.xml" \
    -S "$SCRIPT_DIR/app/src/main/res" \
    -I "$ANDROID_JAR"

# ------------------------------------------------------------------------------
# 2. Compile Java Source Code (KitKat compatible bytecode)
# ------------------------------------------------------------------------------
echo ">>> [2/7] Compiling Java source files..."
javac -source 8 -target 8 \
    -bootclasspath "$ANDROID_JAR" \
    -cp "$ANDROID_JAR" \
    -d "$CLASSES_DIR" \
    $(find "$GEN_DIR" -name "*.java") \
    $(find "$SCRIPT_DIR/app/src/main/java" -name "*.java")

# ------------------------------------------------------------------------------
# 3. Translate Bytecode to Dalvik Executable (classes.dex)
# ------------------------------------------------------------------------------
echo ">>> [3/7] Dexing class files via dx..."
java -jar "$DX_JAR" --dex \
    --output="$APP_BUILD/classes.dex" \
    "$CLASSES_DIR"

# ------------------------------------------------------------------------------
# 4. Package APK Resources & Assets
# ------------------------------------------------------------------------------
echo ">>> [4/7] Packaging APK resources and assets..."
"$AAPT" package -f \
    -M "$SCRIPT_DIR/app/src/main/AndroidManifest.xml" \
    -S "$SCRIPT_DIR/app/src/main/res" \
    -A "$SCRIPT_DIR/app/src/main/assets" \
    -I "$ANDROID_JAR" \
    -F "$APP_BUILD/unaligned_unsigned.apk"

# Add classes.dex to APK
cd "$APP_BUILD"
"$ZIP_BIN" -u unaligned_unsigned.apk classes.dex >/dev/null
cd "$SCRIPT_DIR"

# ------------------------------------------------------------------------------
# 5. ZipAlign APK (4-byte alignment for Android runtime)
# ------------------------------------------------------------------------------
echo ">>> [5/7] Aligning APK (zipalign)..."
"$ZIPALIGN" -f -p 4 \
    "$APP_BUILD/unaligned_unsigned.apk" \
    "$APP_BUILD/aligned_unsigned.apk"

# ------------------------------------------------------------------------------
# 6. Sign APK with Release Keystore (v1 + v2 schemes)
# ------------------------------------------------------------------------------
echo ">>> [6/7] Signing APK with apksigner..."
KEYSTORE="$KEYSTORE_DIR/nemesis_release.keystore"
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair -v \
        -keystore "$KEYSTORE" \
        -storetype JKS \
        -alias nemesis_key \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass nemesis_pass \
        -keypass nemesis_pass \
        -dname "CN=NEMESIS, OU=Automotive, O=HMG, L=Irvine, ST=CA, C=US" >/dev/null 2>&1
fi

FINAL_APK="$SCRIPT_DIR/package/app/AutoProfile.apk"
java -jar "$APKSIGNER_JAR" sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:nemesis_pass \
    --ks-key-alias nemesis_key \
    --key-pass pass:nemesis_pass \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --out "$FINAL_APK" \
    "$APP_BUILD/aligned_unsigned.apk"

# Verify APK Signature
java -jar "$APKSIGNER_JAR" verify --verbose "$FINAL_APK" > "$APP_BUILD/verify.log"
echo "    APK Signature verified: v1=true, v2=true"

# ------------------------------------------------------------------------------
# 7. Assemble and Create NEMESIS Package ZIP (autoprofile.selector.zip)
# ------------------------------------------------------------------------------
echo ">>> [7/8] Assembling NEMESIS package zip..."

# Ensure executable permissions on all shell scripts
chmod 755 package/svc/helper.sh package/scripts/*.sh

OUTPUT_ZIP="$SCRIPT_DIR/autoprofile.selector.zip"
rm -f "$OUTPUT_ZIP"

cd "$SCRIPT_DIR/package"
"$ZIP_BIN" -r -9 "$OUTPUT_ZIP" \
    NEMESIS.data \
    app/AutoProfile.apk \
    svc/helper.sh \
    scripts/post.sh \
    scripts/preun.sh >/dev/null
cd "$SCRIPT_DIR"

# ------------------------------------------------------------------------------
# 8. Create Ready-to-Copy USB Installer (build/usb-stick & autoprofile.selector-usb.zip)
# ------------------------------------------------------------------------------
echo ">>> [8/8] Creating USB installer bundle..."
USB_DIR="$BUILD_DIR/usb-stick"
rm -rf "$USB_DIR"
mkdir -p "$USB_DIR/packages"

# 1. Copy package zip into packages/
cp "$OUTPUT_ZIP" "$USB_DIR/packages/autoprofile.selector.zip"

# 2. Create the USB root trigger descriptor (type=install)
cat > "$USB_DIR/NEMESIS.data" << 'EOF'
[nemesis]
version=1.1
type=install
path=packages/autoprofile.selector.zip
name=Auto Profile Selector
EOF

# 3. Create ready-to-extract USB installer ZIP
USB_ZIP="$SCRIPT_DIR/autoprofile.selector-usb.zip"
rm -f "$USB_ZIP"
cd "$USB_DIR"
"$ZIP_BIN" -r -9 "$USB_ZIP" NEMESIS.data packages/ >/dev/null
cd "$SCRIPT_DIR"

# Mirror to ~/ioniq5_data if directory exists
DATA_DIR="${IONIQ5_DATA_DIR:-$HOME/ioniq5_data}"
if [ -d "$DATA_DIR" ]; then
    cp "$OUTPUT_ZIP" "$DATA_DIR/autoprofile.selector.zip"
    cp "$USB_ZIP" "$DATA_DIR/autoprofile.selector-usb.zip"
fi

# Verify Package Zip Integrity
echo ""
echo "======================================================================"
echo " BUILD SUCCESSFUL!"
echo " Standalone Package: $OUTPUT_ZIP ($(du -h "$OUTPUT_ZIP" | cut -f1))"
echo " USB Installer ZIP:  $USB_ZIP ($(du -h "$USB_ZIP" | cut -f1))"
echo " USB Folder:         $USB_DIR"
echo ""
echo " Package Contents:"
"$UNZIP_BIN" -l "$OUTPUT_ZIP"
echo ""
echo " USB Installer Root Contents:"
"$UNZIP_BIN" -l "$USB_ZIP"
echo "======================================================================"
