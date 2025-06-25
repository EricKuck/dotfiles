{ python3Packages }:

with python3Packages;

buildPythonApplication {
  pname = "prometheus-quadlet-exporter";
  version = "0.0";
  format = "pyproject";

  src = ./.;

  nativeBuildInputs = [ setuptools ];

  propagatedBuildInputs = [
    packaging
    prometheus-client
    systemdunitparser
    pystemd
  ];

  meta = with lib; {
    description = "prometheus-quadlet-exporter";
    mainProgram = "prometheus-quadlet-exporter";
  };
}
