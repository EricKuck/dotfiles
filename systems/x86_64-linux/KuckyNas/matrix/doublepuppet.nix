{
  config,
  lib,
  ...
}:

{
  services.matrix-synapse.settings.app_service_config_files = lib.mkAfter [
    config.sops.templates."doublepuppet-registration".path
  ];

  sops.templates."doublepuppet-registration" = {
    content = ''
      id: doublepuppet
      url: ""
      as_token: ${config.sops.placeholder.doublepuppet-as-token}
      hs_token: ${config.sops.placeholder.doublepuppet-hs-token}
      sender_localpart: doublepuppetbot
      rate_limited: false
      namespaces:
        users:
          - regex: '@.*:kuck\.ing'
            exclusive: false
    '';
    owner = "matrix-synapse";
    group = "matrix-synapse";
    mode = "0440";
  };
}
