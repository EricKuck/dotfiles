{ lib }:
{
  hostedUrls =
    {
      config,
      includeScheme ? true,
      includeBlackboxPath ? false,
    }:
    let
      directCaddyUrls = builtins.filter (item: builtins.match ".*\\*.*" item == null) (
        builtins.attrNames config.services.caddy.virtualHosts
      );

      containerUrls =
        let
          containers = config.home-manager.users."${config.meta.flake.owner}".quadlets.containers;
        in
        builtins.concatLists (
          builtins.map (
            name:
            let
              rawLabels = containers.${name}.containerConfig.labels or [ ];
              labels = if builtins.isAttrs rawLabels then builtins.attrValues rawLabels else rawLabels;
              getLabelValue =
                key:
                let
                  matching = builtins.filter (
                    label:
                    let
                      parts = builtins.match "([^=]+)=(.*)" label;
                    in
                    parts != null && builtins.elemAt parts 0 == key
                  ) labels;
                in
                if matching == [ ] then
                  null
                else
                  let
                    parts = builtins.match "([^=]+)=(.*)" (builtins.elemAt matching 0);
                  in
                  builtins.elemAt parts 1;
              host = getLabelValue "caddy.host";
              path =
                if includeBlackboxPath then
                  let
                    val = getLabelValue "blackbox.path";
                  in
                  if val == null then "" else val
                else
                  "";
            in
            if host != null then [ "${host}${path}" ] else [ ]
          ) (builtins.attrNames containers)
        );

      combinedUrls = directCaddyUrls ++ containerUrls;

      finalUrls =
        if includeScheme then builtins.map (item: "https://${item}") combinedUrls else combinedUrls;
    in
    finalUrls;
}
