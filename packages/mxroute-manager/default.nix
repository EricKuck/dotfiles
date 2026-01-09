{
  lib,
  pkgs,
  ...
}:
let
  fs = lib.fileset;
in
pkgs.python3Packages.buildPythonApplication {
  pname = "mxroute-manager";
  version = "0.1.0";
  format = "other";

  src = ./.;

  propagatedBuildInputs = with pkgs.python3Packages; [
    flask
    requests
    gunicorn
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/mxroute-manager

    cp -r . $out/lib/mxroute-manager/

    cat > $out/bin/mxroute-manager << EOF
    #!${pkgs.python3}/bin/python3
    import sys
    import os
    sys.path.insert(0, "$out/lib/mxroute-manager")
    os.chdir("$out/lib/mxroute-manager")
    from app import app
    if __name__ == "__main__":
        app.run(host="0.0.0.0", port=2121, debug=False)
    EOF

    chmod +x $out/bin/mxroute-manager

    # Create gunicorn production wrapper
    cat > $out/bin/mxroute-manager-gunicorn << EOF
    #!/bin/sh
    cd $out/lib/mxroute-manager
    exec ${pkgs.python3Packages.gunicorn}/bin/gunicorn \
      -w 4 \
      -b 0.0.0.0:2121 \
      --timeout 30 \
      --keep-alive 2 \
      --max-requests 1000 \
      --max-requests-jitter 100 \
      app:app "\$@"
    EOF

    chmod +x $out/bin/mxroute-manager-gunicorn

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
