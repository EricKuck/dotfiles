{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "podman-compose";
  version = "unstable-2024-05-07";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "EricKuck";
    repo = "podman-compose";
    rev = "e7450f7b091bf899be3e7bd03018d426ff3a5039";
    hash = "sha256-vr6cL5REeQI2cCdslPkisRjThC092X7VgBrw/ziYheg=";
  };

  nativeBuildInputs = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
  ];

  propagatedBuildInputs = with python3.pkgs; [
    python-dotenv
    pyyaml
  ];

  pythonImportsCheck = [ "podman_compose" ];

  meta = with lib; {
    description = "A script to run docker-compose.yml using podman";
    homepage = "https://github.com/EricKuck/podman-compose";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ ];
    mainProgram = "podman-compose";
  };
}
