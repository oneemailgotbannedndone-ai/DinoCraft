#!/bin/zsh
# Builds DinoCraft Mobile, the offline iPhone/iPad edition, on a Mac with Xcode installed.
#
#   Scripts/build_ios.sh            device build → dist/DinoCraft-Mobile.ipa (unsigned, for AltStore / SideStore)
#   Scripts/build_ios.sh simulator  simulator build → dist/ios-simulator/DinoCraft.app
#
# Sideloading tools sign the .ipa with your own Apple ID when they install it, so it isn't signed here
# (apart from the ad-hoc signature every arm64 binary needs).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

KIND="${1:-device}"
VERSION="1.0"
BUILD_NUMBER="${DINOCRAFT_BUILD:-$(date +%Y%m%d%H%M)}"
MIN_IOS="16.0"

case "$KIND" in
  device)    SDK=iphoneos;        TRIPLE="arm64-apple-ios${MIN_IOS}";           PLATFORM=iPhoneOS ;;
  simulator) SDK=iphonesimulator; TRIPLE="arm64-apple-ios${MIN_IOS}-simulator"; PLATFORM=iPhoneSimulator ;;
  *) echo "usage: $0 [device|simulator]" >&2; exit 2 ;;
esac

SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
SCRATCH=".build-ios-$KIND"
echo "▸ Compiling DinoCraftMobile ($KIND, $TRIPLE)"
swift build -c release --product DinoCraftMobile --sdk "$SDK_PATH" --triple "$TRIPLE" --scratch-path "$SCRATCH"
BIN="$(swift build -c release --product DinoCraftMobile --sdk "$SDK_PATH" --triple "$TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)/DinoCraftMobile"

APP="dist/ios-$KIND/DinoCraft.app"
echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP"
cp "$BIN" "$APP/DinoCraft"
# On iOS the resources sit at the top of the app bundle (Bundle.main.resourceURL is the .app itself).
for dir in Data Textures TexturePacks Sounds Music Shaders Art; do
  [ -d "Resources/$dir" ] && cp -R "Resources/$dir" "$APP/"
done
# The game plays the .m4a version of a song when there is one, so leave out the larger .wav copies.
for wav in "$APP"/Music/*.wav; do
  [ -f "${wav%.wav}.m4a" ] && rm "$wav"
done

# App icons from the 1024px artwork.
ICON_SRC="Resources/Art/icon_1024.png"
if [ -f "$ICON_SRC" ]; then
  sips -z 120 120 "$ICON_SRC" --out "$APP/AppIcon60x60@2x.png" >/dev/null
  sips -z 180 180 "$ICON_SRC" --out "$APP/AppIcon60x60@3x.png" >/dev/null
  sips -z 152 152 "$ICON_SRC" --out "$APP/AppIcon76x76@2x~ipad.png" >/dev/null
  sips -z 167 167 "$ICON_SRC" --out "$APP/AppIcon83.5x83.5@2x~ipad.png" >/dev/null
fi

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DinoCraft</string>
  <key>CFBundleDisplayName</key><string>DinoCraft</string>
  <key>CFBundleIdentifier</key><string>com.dinocraft.mobile</string>
  <key>CFBundleExecutable</key><string>DinoCraft</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleSupportedPlatforms</key><array><string>${PLATFORM}</string></array>
  <key>MinimumOSVersion</key><string>${MIN_IOS}</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string><string>metal</string></array>
  <key>UISupportedInterfaceOrientations</key><array>
    <string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string>
  </array>
  <key>UISupportedInterfaceOrientations~ipad</key><array>
    <string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string>
  </array>
  <key>UIRequiresFullScreen</key><true/>
  <key>UIStatusBarHidden</key><true/>
  <key>UIViewControllerBasedStatusBarAppearance</key><true/>
  <key>UILaunchScreen</key><dict/>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>CFBundleIcons</key><dict>
    <key>CFBundlePrimaryIcon</key><dict>
      <key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key><dict>
    <key>CFBundlePrimaryIcon</key><dict>
      <key>CFBundleIconFiles</key><array><string>AppIcon60x60</string><string>AppIcon76x76</string><string>AppIcon83.5x83.5</string></array>
    </dict>
  </dict>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/PkgInfo"

echo "▸ Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
echo "  architectures: $(lipo -archs "$APP/DinoCraft")"
du -sh "$APP" | awk '{print "  app size: " $1}'

if [[ "$KIND" == device ]]; then
  echo "▸ Packaging dist/DinoCraft-Mobile.ipa"
  STAGE="$(mktemp -d)"
  mkdir -p "$STAGE/Payload"
  ditto "$APP" "$STAGE/Payload/DinoCraft.app"
  rm -f dist/DinoCraft-Mobile.ipa
  (cd "$STAGE" && zip -qry "$ROOT/dist/DinoCraft-Mobile.ipa" Payload)
  rm -rf "$STAGE"
  du -h dist/DinoCraft-Mobile.ipa | awk '{print "  ipa size: " $1}'
fi
echo "✓ Built $APP"
