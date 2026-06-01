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
      owner = "EricKuck";
      repo = "mautrix-gvoice";
      rev = "988ae443369ced993e7d3d5036d3f5a50c098063";
      hash = "sha256-u0DIPvwl35Q+m+Zg68zxoFd3q867VOvAamH8BlEBYac=";
    };

    vendorHash = "sha256-iNOMX7gonvkQSH6r0tCtqD71fyUfQfHmclrWbH11XiU=";

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
