{ python3Packages }:

with python3Packages;

buildPythonApplication {
  pname = "prometheus-nixos-exporter";
  version = "0.0";
  format = "pyproject";

  src = ./.;

  nativeBuildInputs = [ setuptools ];

  propagatedBuildInputs = [
    packaging
    prometheus-client
  ];

  meta = with lib; {
    description = "prometheus-nixos-exporter";
    mainProgram = "prometheus-nixos-exporter";
  };
}
