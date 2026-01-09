{
  lib,
  pkgs,
  ...
}:
let
  fs = lib.fileset;

  python = pkgs.python3.withPackages (
    ps: with ps; [
      flask
      requests
      gunicorn
    ]
  );
in
pkgs.stdenv.mkDerivation {
  pname = "mxroute-manager";
  version = "0.1.0";
  format = "other";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  buildInputs = [ python ];

  installPhase = ''
     runHook preInstall

     mkdir -p $out/bin $out/lib/mxroute-manager

     cp -r . $out/lib/mxroute-manager/

     makeWrapper ${python}/bin/python $out/bin/mxroute-manager \
       --add-flags "$out/lib/mxroute-manager/app.py" \
       --chdir "$out/lib/mxroute-manager" \
       --set FLASK_APP "app.py"

    makeWrapper ${python}/bin/gunicorn $out/bin/mxroute-manager-gunicorn \
       --add-flags "app:app" \
       --chdir "$out/lib/mxroute-manager" \
       --add-flags "--timeout 30" \
       --add-flags "--keep-alive 2" \
       --add-flags "--max-requests 1000" \
       --add-flags "--max-requests-jitter 100"

     runHook postInstall
  '';

  doCheck = false;

  meta = with lib; {
    description = "Web application for managing MXRoute email forwarders";
    homepage = "https://github.com/yourusername/mxroute-manager";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
    mainProgram = "mxroute-manager";
  };
}
