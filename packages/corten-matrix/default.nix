{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  libheif,
  ffmpeg,
}:

# Upstream ships the bridge as a single self-contained binary (Go + a static
# rustpush core). Since 1.3.6 it can't be built from source at all: the code
# that registers with Apple (on macOS, by reading this Mac's hardware
# identifiers) is closed-source and only ships in the release binaries.
#
# The binary only links system frameworks. Its two optional runtime
# dependencies are resolved at runtime: libheif is dlopen()ed by bare name
# (so DYLD_FALLBACK_LIBRARY_PATH decides where it comes from) and ffmpeg is
# looked up on PATH. The wrapper points both at nixpkgs instead of Homebrew.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "corten-matrix";
  version = "1.3.6";

  src = fetchurl {
    url = "https://github.com/lrhodin/corten-matrix/releases/download/${finalAttrs.version}/corten-matrix-macos";
    hash = "sha256-KYrN7yIFB0vGqi5VfODLIVayx5zIEpTLRui3/pNOMdo=";
  };

  dontUnpack = true;
  # Keep the upstream ad-hoc signature intact; macOS tracks the binary by it.
  dontStrip = true;
  dontFixup = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/corten-matrix

    # The wrapper is a Nix bash script, not a platform binary, so DYLD_* is
    # passed through to the bridge even when launchd starts it via /bin/sh.
    makeWrapper $out/libexec/corten-matrix $out/bin/corten-matrix \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg ]} \
      --prefix DYLD_FALLBACK_LIBRARY_PATH : ${lib.getLib libheif}/lib

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/corten-matrix help >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Matrix-iMessage puppeting bridge built on rustpush";
    homepage = "https://github.com/lrhodin/corten-matrix";
    # AGPL source plus the closed-source registration code linked in.
    license = with lib.licenses; [
      agpl3Plus
      unfree
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "corten-matrix";
  };
})
