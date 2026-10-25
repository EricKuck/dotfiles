{
  config,
  lib,
  inputs,
  ...
}:

# corten-matrix (iMessage) runs on IRLBuild, since it needs a Mac. Only the
# appservice registration lives here; everything about the bridge itself is
# read from the IRLBuild configuration so the two can't drift apart.
let
  irlbuild = inputs.self.darwinConfigurations.IRLBuild.config;
  bridge = irlbuild.custom.services.corten-matrix;
  appservice = bridge.settings.appservice;
  domain = lib.escapeRegex bridge.homeserver.domain;
  ghostRegex = lib.replaceStrings [ "{{.}}" ] [ ".*" ] appservice.username_template;
in
{
  services.matrix-synapse.settings.app_service_config_files = lib.mkAfter [
    config.sops.templates."corten-matrix-registration".path
  ];

  sops.secrets = {
    corten-matrix-as-token = { };
    corten-matrix-hs-token = { };
  };

  sops.templates."corten-matrix-registration" = {
    content = ''
      id: ${appservice.id}
      url: http://${irlbuild.meta.ipAddress}:${toString bridge.port}
      as_token: ${config.sops.placeholder.corten-matrix-as-token}
      hs_token: ${config.sops.placeholder.corten-matrix-hs-token}
      sender_localpart: ${appservice.bot.username}
      rate_limited: false
      namespaces:
        users:
          - regex: '^@${appservice.bot.username}:${domain}$'
            exclusive: true
          - regex: '^@${ghostRegex}:${domain}$'
            exclusive: true
      de.sorunome.msc2409.push_ephemeral: true
      receive_ephemeral: true
    '';
    owner = "matrix-synapse";
    group = "matrix-synapse";
    mode = "0440";
  };
}
