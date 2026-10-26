{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  ffmpeg-headless,
}:

buildGoModule (finalAttrs: {
  pname = "mautrix-imessage";
  version = "0.2.1-unstable-2026-10-26";

  src = fetchFromGitHub {
    owner = "EricKuck";
    repo = "imessage";
    rev = "92ab3d3c100607539328be897a85e3970cbfaea2";
    hash = "sha256-A3MALl9L6PLE84ZzushgFO0RPObDD45BcVPYrvx8x3I=";
  };

  vendorHash = "sha256-AMmJvgzQ48/K0Ug4uCX0KnO69pBvzvZ6OO0oE+747xY=";

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
