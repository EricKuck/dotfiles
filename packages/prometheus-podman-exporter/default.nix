{
  lib,
  buildGoModule,
  fetchFromGitHub,
  pkg-config,
  btrfs-progs,
  gpgme,
  lvm2,
  runc,
  crun,
  conmon,
  netavark,
  makeWrapper,
}:

buildGoModule rec {
  pname = "prometheus-podman-exporter";
  version = "1.17.1";

  src = fetchFromGitHub {
    owner = "containers";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-5+1rGe9xv0ZVkmLr7pCteuN1DA+oozi/GSyQlQikrWA=";
  };

  vendorHash = null;

  ldflags =
    let
      pkg = "github.com/containers/prometheus-podman-exporter";
    in
    [
      "-X ${pkg}/cmd.buildVersion=${version}"
      "-X ${pkg}/cmd.buildRevision=${src.rev}"
      "-X ${pkg}/cmd.buildBranch=unknown"
    ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    btrfs-progs
    gpgme
    lvm2
  ];

  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/prometheus-podman-exporter \
      --run "export CONTAINER_HOST=\"unix:///run/podman-rootless-proxy/podman.sock\"" \
      --prefix PATH : ${
        lib.makeBinPath [
          runc
          crun
          conmon
          netavark
        ]
      }
  '';

  meta = with lib; {
    description = "Prometheus exporter for podman environments exposing containers, pods, images, volumes and networks information.";
    homepage = "https://github.com/containers/prometheus-podman-exporter";
    license = licenses.asl20;
    maintainers = with maintainers; [ ataraxiasjel ];
    mainProgram = "prometheus-podman-exporter";
  };
}
