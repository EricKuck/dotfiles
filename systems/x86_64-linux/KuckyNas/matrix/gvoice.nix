{
  config,
  lib,
  pkgs,
  ...
}:

let
  mautrix-gvoice = pkgs.buildGoModule {
    pname = "mautrix-gvoice";
    version = "0.2605.0";

    src = pkgs.fetchFromGitHub {
      owner = "mautrix";
      repo = "gvoice";
      rev = "6317e1dfed3257a0757f894a6b1af089bf8851d8";
      hash = "sha256-4L2sHyCZ1dNkBRvYCz+xc5Kpa1i1Drub3eoNQNigbxk=";
    };

    vendorHash = "sha256-Xg5NEXXuBPYgaju41aQMYCZW/08cSx/AwRo6AEgOk6w=";

    buildInputs = [ pkgs.olm ];

    doCheck = false;

    meta = with lib; {
      description = "A Matrix-Google Voice puppeting bridge";
      homepage = "https://github.com/mautrix/gvoice";
      license = licenses.agpl3Plus;
    };
  };

  bridgeLib = import ./bridge.nix { inherit config lib; };
in
{
  services.custom.matrix-bridges.gvoice = bridgeLib.mkBridgeConfig {
    service = "gvoice";
    serviceName = "Google Voice";
    package = mautrix-gvoice;
    commandPrefix = "!gv";
    botAvatar = "mxc://maunium.net/eFEQQPTclYFeRMVZJkNwaARY";

    settings = {
      network = {
        displayname_template = "{{ or .Contact.Name .Name }}";
        number_in_topic = true;
      };
    };
  };
}
