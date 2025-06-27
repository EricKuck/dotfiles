{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "prometheus-jellyfin-exporter";
  version = "1.3.6";

  src = fetchFromGitHub {
    owner = "rebelcore";
    repo = "jellyfin_exporter";
    rev = "v${version}";
    hash = "sha256-SAjI3rrT83JFZTXULHJWv3mpdnxPraX+eCNyeSGqDV0=";
  };

  vendorHash = "sha256-/VCE2C8EismFg1puajWmBK8qf3hLYXzywA1R/qqAMr0=";
  doCheck = false;

  meta = with lib; {
    description = "Jellyfin Media System metrics exporter for prometheus.";
    homepage = "https://github.com/rebelcore/jellyfin_exporter";
    mainProgram = "jellyfin_exporter";
  };
}
