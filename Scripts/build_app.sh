#!/bin/zsh
# Builds DinoCraft.app — a native arm64 macOS application bundle.
#
#   Scripts/build_app.sh            release build → dist/DinoCraft.app
#   Scripts/build_app.sh --assets   regenerate textures/sounds/music/icon first
#   Scripts/build_app.sh --test     run the core self-test suite first
#   Scripts/build_app.sh --install  also copy the app into /Applications (replacing an older copy)
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

VERSION="0.10.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
INSTALL=0
APP="dist/DinoCraft.app"

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --assets)
      echo "▸ Generating assets"
      swift build -c release --arch arm64 --product AssetForge
      .build/release/AssetForge
      ;;
    --test)
      echo "▸ Running self-tests"
      swift build -c release --arch arm64 --product DinoCraftSelfTest
      .build/release/DinoCraftSelfTest
      ;;
  esac
done

echo "▸ Compiling DinoCraft (release, arm64)"
swift build -c release --arch arm64 --product DinoCraft
BIN="$(swift build -c release --arch arm64 --show-bin-path)/DinoCraft"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DinoCraft"
for dir in Data Textures TexturePacks Sounds Music Shaders Art; do
  [ -d "Resources/$dir" ] && cp -R "Resources/$dir" "$APP/Contents/Resources/"
done
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DinoCraft</string>
  <key>CFBundleDisplayName</key><string>DinoCraft</string>
  <key>CFBundleIdentifier</key><string>com.dinocraft.game</string>
  <key>CFBundleExecutable</key><string>DinoCraft</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSRequiresNativeExecution</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.adventure-games</string>
  <key>GCSupportsGameMode</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>DinoCraft finds and hosts games on your local network so you can play with friends.</string>
  <key>NSBonjourServices</key><array><string>_dinocraft._tcp</string></array>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>DinoCraft — an original voxel adventure.</string>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

# DinoCraft Launcher: the same program in launcher mode (news, updates, skins, the guide),
# sharing DinoCraft.app's resources. Its Play button opens DinoCraft.app.
LAUNCHER="dist/DinoCraft Launcher.app"
echo "▸ Assembling $LAUNCHER"
rm -rf "$LAUNCHER"
mkdir -p "$LAUNCHER/Contents/MacOS" "$LAUNCHER/Contents/Resources"
cp "$BIN" "$LAUNCHER/Contents/MacOS/DinoCraft Launcher"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$LAUNCHER/Contents/Resources/"
sed -e 's|<string>DinoCraft</string>|<string>DinoCraft Launcher</string>|g' \
    -e 's|com.dinocraft.game|com.dinocraft.launcher|' "$APP/Contents/Info.plist" > "$LAUNCHER/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$LAUNCHER"

echo "▸ Verifying"
codesign --verify --strict "$APP"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/DinoCraft")"
echo "  architectures: $ARCHS"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "  ✗ expected a native arm64 binary" >&2
  exit 1
fi
echo "  linked libraries:"
otool -L "$APP/Contents/MacOS/DinoCraft" | tail -n +2 | sed 's/^/   /'
du -sh "$APP" | awk '{print "  bundle size: " $1}'
echo "✓ Built $APP"

if [[ "$INSTALL" == 1 ]]; then
  DEST="/Applications/DinoCraft.app"
  echo "▸ Installing to $DEST"
  pkill -x DinoCraft 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  rm -rf "/Applications/DinoCraft Launcher.app"
  ditto "$LAUNCHER" "/Applications/DinoCraft Launcher.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
  touch "$DEST"
  echo "✓ Installed $VERSION ($BUILD_NUMBER) to $DEST"
fi
