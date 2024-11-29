{
  lib,
  stdenv,
  pkgs,
  undmg,
  fetchFromGitHub,
}:

stdenv.mkDerivation rec {
  pname = "mic-switch";
  version = "1.2";

  src = pkgs.fetchurl {
    url = "https://github.com/dstd/micSwitch/releases/download/1.2/micSwitch.1.2.dmg";
    sha256 = "14bdfkqvn06fqapb43fnxynblrchs9sh4j2fh700gp486vnk624k";
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = "micSwitch.app";

  installPhase = ''
    APP="$out/Applications/micSwitch.app"
    if [ -d "$APP" ]; then
      exit 0
    fi

    runHook preInstall
    mkdir -p $APP
    cp -R . $APP
    runHook postInstall
  '';

  meta = {
    description = "MacOS menu bar application for the mic mute/unmute with single click or shortcut with walkie-talkie style support";
    homepage = "https://github.com/dstd/micSwitch";
    license = lib.licenses.unfree; # FIXME: nix-init did not find a license
    maintainers = with lib.maintainers; [ ];
    mainProgram = "mic-switch";
    platforms = lib.platforms.all;
  };
}
