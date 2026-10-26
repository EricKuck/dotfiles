{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

# BlueBubbles Server exposes this Mac's iMessage over a REST/socket API; here
# it's the backend for mautrix-imessage's BlueBubbles connector. It runs in the
# imessage-bridge VM (SIP disabled) so its Private API can be used.
#
# Pinned to 1.9.9, whose Private API helper works on macOS 15 but not 26.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "bluebubbles-server";
  version = "1.9.9";

  src = fetchurl {
    url = "https://github.com/BlueBubblesApp/bluebubbles-server/releases/download/v${finalAttrs.version}/BlueBubbles-${finalAttrs.version}-arm64.dmg";
    hash = "sha256-+v1lDIg/UudJSmYl5FJJ8hRNGXN4pNVxQ8z2GYuy6GI=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  # Keep the upstream signature intact: the app uses the hardened runtime, and
  # macOS ties its privacy permissions (Full Disk Access, ...) to it.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -R BlueBubbles.app $out/Applications/

    runHook postInstall
  '';

  meta = {
    description = "Server for using iMessage on non-Apple devices";
    homepage = "https://bluebubbles.app";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
})
