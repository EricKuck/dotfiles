{
  config,
  lib,
  pkgs,
  ...
}:

let
  mautrix-gvoice = pkgs.buildGoModule {
    pname = "mautrix-gvoice";
    version = "0.2511.0";

    src = pkgs.fetchFromGitHub {
      owner = "EricKuck";
      repo = "mautrix-gvoice";
      rev = "efb1c3c221a505fcc707875434fc59d195a025e1";
      hash = "sha256-L7DtHuQaoL+3c66uW42YD8ZMM6ZjdOkC67+BwDt6WLw=";
    };

    vendorHash = "sha256-jhPp1AjG8WI+z2ZMkuCXgi88pFl8lqLEZPeXzBcWXis=";

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
        displayname_template = "{{or .Name .PhoneNumber \"Unknown user\"}}";
        number_in_topic = true;
      };
    };
  };
}
