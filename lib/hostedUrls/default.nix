{ lib }:
{
  hostedUrls =
    {
      config,
      includeScheme ? true,
      includeBlackboxPath ? false,
    }:
    let
      containers = config.home-manager.users."${config.meta.flake.owner}".quadlets.containers;

      getLabelValue =
        labels: key:
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
          builtins.elemAt (builtins.match "([^=]+)=(.*)" (builtins.elemAt matching 0)) 1;

      normalizeLabels =
        rawLabels: if builtins.isAttrs rawLabels then builtins.attrValues rawLabels else rawLabels;

      directCaddyUrls = builtins.filter (item: builtins.match ".*\\*.*" item == null) (
        builtins.attrNames config.services.caddy.virtualHosts
      );

      containerData = builtins.map (
        name:
        let
          rawLabels = containers.${name}.containerConfig.labels or [ ];
          labels = normalizeLabels rawLabels;
          host = getLabelValue labels "caddy.host";
          path =
            if includeBlackboxPath then
              let
                val = getLabelValue labels "blackbox.path";
              in
              if val == null then "" else val
            else
              "";
          allow40x = getLabelValue labels "blackbox.allow40x" == "true";
        in
        if host != null then
          {
            url = "${host}${path}";
            inherit allow40x;
          }
        else
          null
      ) (builtins.attrNames containers);

      validContainerData = builtins.filter (x: x != null) containerData;

      combinedUrls =
        builtins.map (url: {
          url = url;
          allow40x = false;
        }) directCaddyUrls
        ++ validContainerData;

      withScheme = builtins.map (
        item:
        let
          full = if includeScheme then "https://${item.url}" else item.url;
        in
        item // { url = full; }
      ) combinedUrls;

      urlsAllow40x = builtins.map (x: x.url) (builtins.filter (x: x.allow40x) withScheme);
      urlsStrict = builtins.map (x: x.url) (builtins.filter (x: !x.allow40x) withScheme);
    in
    {
      all = urlsStrict ++ urlsAllow40x;
      strict = urlsStrict;
      allow40x = urlsAllow40x;
    };
}
