{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  ffmpeg-headless,
}:

buildGoModule (finalAttrs: {
  pname = "mautrix-imessage";
  version = "0.2.0-unstable-2026-10-26";

  src = fetchFromGitHub {
    owner = "EricKuck";
    repo = "imessage";
    rev = "3356e13301d4ba28133c7999e0d680601f1f9c97";
    hash = "sha256-rL7cKlTRD59QxKE12nLVKgweTHQIqatWfFIAmJ49LTo=";
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
