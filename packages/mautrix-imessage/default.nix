{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  ffmpeg-headless,
}:

buildGoModule (finalAttrs: {
  pname = "mautrix-imessage";
  version = "0.2.1-unstable-2026-11-18";

  src = fetchFromGitHub {
    owner = "EricKuck";
    repo = "imessage";
    rev = "c3da97ec1fce2fca79f91d8efb8fca22c36ab587";
    hash = "sha256-KRZh1JOQW83PnriEi7S/hYRKkbOv6MN+c2uOLOS0ZGc=";
  };

  vendorHash = "sha256-dTekkmiuvBlV+5IMQjdfau0zBNTgrPFH/kMlleZ65Ac=";

  subPackages = [ "cmd/mautrix-imessage" ];

  # Pure-Go olm instead of the deprecated libolm.
  tags = [ "goolm" ];

  nativeBuildInputs = [ makeWrapper ];

  ldflags = [ "-X main.Commit=${finalAttrs.src.rev}" ];

  # ffmpeg converts voice messages between Matrix (ogg) and iMessage (m4a).
  postInstall = ''
    wrapProgram $out/bin/mautrix-imessage --prefix PATH : ${lib.makeBinPath [ ffmpeg-headless ]}
  '';

  doCheck = false;

  meta = {
    description = "A Matrix-iMessage puppeting bridge using BlueBubbles";
    homepage = "https://github.com/EricKuck/imessage";
    license = lib.licenses.agpl3Plus;
    mainProgram = "mautrix-imessage";
  };
})
