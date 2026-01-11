{ lib }:
{
  hostedUrls =
    {
      config,
      includeScheme ? true,
      forBlackbox ? false,
      includeDirectCaddyUrls ? true,
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

      portFromPublishSpec =
        spec:
        let
          portSpec = toString spec;
          noProtocolPortSpec = builtins.elemAt (builtins.match "^([^/]+)(/.*)?$" portSpec) 0;
          # ip:host:container
          m3 = builtins.match "^[^:]+:([0-9]+):[0-9]+$" noProtocolPortSpec;
          # host:container
          m2 = builtins.match "^([0-9]+):[0-9]+$" noProtocolPortSpec;
          # single port "8080" (treat as host port)
          m1 = builtins.match "^([0-9]+)$" noProtocolPortSpec;
        in
        if m3 != null then
          builtins.elemAt m3 0
        else if m2 != null then
          builtins.elemAt m2 0
        else if m1 != null then
          builtins.elemAt m1 0
        else
          null;

      getQuadletPort =
        container:
        let
          candidate =
            container.containerConfig.publishPorts or container.containerConfig.ports
              or container.containerConfig.port or null;

          vals = if builtins.isList candidate then candidate else [ candidate ];

          parsed = builtins.filter (x: x != null) (builtins.map portFromPublishSpec vals);
        in
        if parsed == [ ] then null else builtins.elemAt parsed 0;

      blackboxConfig = config.custom.blackboxConfig or { };
      disabledUrls = blackboxConfig.disabled or [ ];
      urlPaths = blackboxConfig.paths or { };
      allow40xUrls = blackboxConfig.allow40x or [ ];

      directCaddyUrls =
        if includeDirectCaddyUrls then
          builtins.filter (
            item:
            let
              hasWildcard = builtins.match ".*\\*.*" item != null;
              isDisabled = builtins.elem item disabledUrls;
            in
            !hasWildcard && (!isDisabled || !forBlackbox)
          ) (builtins.attrNames config.services.caddy.virtualHosts)
        else
          [ ];

      containerData = builtins.map (
        name:
        let
          rawLabels = containers.${name}.containerConfig.labels or [ ];
          labels = normalizeLabels rawLabels;
          host = getLabelValue labels "caddy.host";
          path =
            if forBlackbox then
              let
                val = getLabelValue labels "blackbox.path";
              in
              if val == null then "" else val
            else
              "";
          allow40x = getLabelValue labels "blackbox.allow40x" == "true";
          blackboxDisabled = getLabelValue labels "blackbox.disabled" == "true";

          labelPort = getLabelValue labels "caddy.port";
          portStr = if labelPort != null then labelPort else getQuadletPort containers.${name};
          port = builtins.fromJSON portStr;
        in
        if host != null && (!blackboxDisabled || !forBlackbox) then
          {
            url = "${host}${path}";
            inherit allow40x;
            inherit port;
            inherit blackboxDisabled;
          }
        else
          null
      ) (builtins.attrNames containers);

      validContainerData = builtins.filter (x: x != null) containerData;

      allUrls =
        builtins.map (url: {
          url = url;
          allow40x = false;
        }) directCaddyUrls
        ++ validContainerData;

      # Remove duplicate URLs - can happen as each podman quadlet with a caddy config ultimately gets added to the directCaddyUrls eventually
      urlMap = builtins.listToAttrs (
        builtins.map (item: {
          name = item.url;
          value = item;
        }) allUrls
      );

      combinedUrls = builtins.attrValues urlMap;

      withScheme = builtins.map (
        item:
        let
          full = if includeScheme then "https://${item.url}" else item.url;
        in
        item // { url = full; }
      ) combinedUrls;

      strictItems = builtins.filter (x: !x.allow40x) withScheme;
      allow40xItems = builtins.filter (x: x.allow40x) withScheme;
    in
    {
      all = strictItems ++ allow40xItems;
      strict = strictItems;
      allow40x = allow40xItems;
    };
}
