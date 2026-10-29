{
  lib,
  stdenv,
  fetchFromGitHub,
  apple-sdk_15,
  libicns,
  rcodesign,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "trickpad";
  version = "0.14.1";

  src = fetchFromGitHub {
    owner = "nweii";
    repo = "trickpad";
    tag = "v${finalAttrs.version}";
    hash = "sha256-RrFr0gFAirk9uWQXHqgVT6GQJwjo61CXydLey72cWPw=";
  };

  nativeBuildInputs = [
    libicns
    rcodesign
  ];
  buildInputs = [ apple-sdk_15 ];

  # Sources come from build.sh's first clang call so version bumps pick up new files.
  buildPhase = ''
    runHook preBuild

    sources=$(sed -n '/^clang \\/,/-o "\$MACOS_DIR/{p;/-o "\$MACOS_DIR/q;}' scripts/build.sh \
      | grep -oE '"\$(ROOT|SRC_ROOT)/[^"]+\.(m|c)"' \
      | tr -d '"' \
      | sed -e 's|\$SRC_ROOT|src/jitouch/Jitouch|' -e 's|\$ROOT/||')

    $CC \
      -mmacosx-version-min=11.0 \
      -fobjc-exceptions \
      -fno-objc-arc \
      -Isrc/jitouch/Jitouch \
      -Isrc \
      -Ithird_party/tomlc17 \
      -F"$SDKROOT/System/Library/PrivateFrameworks" \
      -framework Cocoa \
      -framework Carbon \
      -framework ApplicationServices \
      -framework AudioToolbox \
      -framework AVFAudio \
      -framework IOKit \
      -framework ScriptingBridge \
      -framework MultitouchSupport \
      $sources \
      -o Trickpad

    $CC \
      -mmacosx-version-min=11.0 \
      -fblocks \
      -fobjc-exceptions \
      -fno-objc-arc \
      -framework Foundation \
      src/TraceAnalyzer.m \
      -o analyze-trace

    icons=assets/marketing/exports/macOS/default
    png2icns Trickpad.icns $icons/Trickpad-{16,32,128,256,512,1024}.png

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/Applications/Trickpad.app/Contents
    mkdir -p $app/MacOS $app/Resources
    cp Trickpad $app/MacOS/
    cp analyze-trace Trickpad.icns config.default.toml config-notes.default.md \
      Trickpad-menu-bar-icon.svg scripts/system-gestures.sh $app/Resources/

    cat > $app/Info.plist <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>Trickpad</string>
      <key>CFBundleIdentifier</key>
      <string>fyi.thirdwind.trickpad</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>Trickpad</string>
      <key>CFBundleDisplayName</key>
      <string>Trickpad</string>
      <key>CFBundleIconFile</key>
      <string>Trickpad</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>${finalAttrs.version}</string>
      <key>CFBundleVersion</key>
      <string>${finalAttrs.version}</string>
      <key>LSMinimumSystemVersion</key>
      <string>11.0</string>
      <key>LSUIElement</key>
      <true/>
    </dict>
    </plist>
    PLIST

    runHook postInstall
  '';

  # Binary form of `designated => identifier "fyi.thirdwind.trickpad"`, so the
  # Accessibility grant survives rebuilds like upstream's build.sh intends.
  postFixup = ''
    printf '\xfa\xde\x0c\x00\x00\x00\x00\x2c\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x16fyi.thirdwind.trickpad\x00\x00' > requirement.bin
    rcodesign sign \
      --binary-identifier fyi.thirdwind.trickpad \
      --code-requirements-path requirement.bin \
      $out/Applications/Trickpad.app
  '';

  meta = {
    description = "Turns Magic Mouse and Magic Trackpad gestures into keyboard shortcuts and actions";
    homepage = "https://github.com/nweii/trickpad";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.darwin;
  };
})
