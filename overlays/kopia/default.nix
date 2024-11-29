# #TODO: ditch when nixpkgs has >= 0.18.2
{
  lib,
  ...
}:

_final: prev: {
  kopia = prev.buildGoModule rec {
    pname = "kopia";
    version = "0.18.2";

    src = prev.fetchFromGitHub {
      owner = "kopia";
      repo = "kopia";
      rev = "v${version}";
      hash = "sha256-7gQlBLmHvqsXXmSYllfsDJRx9VjW0AH7bXf6cG6lGOI=";
    };

    vendorHash = "sha256-lCUEL7rtnv8/86ZTHM4HsYplDnWj1xsFh83JKW6qRrk=";

    ldflags = [
      "-s"
      "-w"
      "-X=github.com/kopia/kopia/repo.BuildVersion=${version}"
      "-X=github.com/kopia/kopia/repo.BuildInfo=${src.rev}"
    ];

    doCheck = false;
    doInstallCheck = false;

    meta = {
      description = "Cross-platform backup tool for Windows, macOS & Linux with fast, incremental backups, client-side end-to-end encryption, compression and data deduplication. CLI and GUI included";
      homepage = "git@github.com:kopia/kopia.git";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [ ];
      mainProgram = "kopia";
    };
  };
}
