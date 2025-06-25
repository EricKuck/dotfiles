let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs.prometheus-client
      python-pkgs.systemdunitparser
      python-pkgs.pystemd
    ]))
  ];
}
