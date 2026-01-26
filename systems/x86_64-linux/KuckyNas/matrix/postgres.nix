{
  pkgs,
  ...
}:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    initdbArgs = [
      "--locale=C"
      "--encoding=UTF8"
    ];

    ensureDatabases = [
      "matrix-synapse"
      "matrix-mas"
    ];

    ensureUsers = [
      {
        name = "matrix-synapse";
        ensureDBOwnership = true;
      }
      {
        name = "matrix-mas";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.matrix-synapse = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };

  systemd.services.postgresql-matrix-extensions = {
    description = "Create PostgreSQL extensions for Matrix";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };

    script = ''
      while ! ${pkgs.postgresql_16}/bin/psql -d postgres -c "SELECT 1" > /dev/null 2>&1; do
        sleep 1
      done

      ${pkgs.postgresql_16}/bin/psql -d matrix-synapse -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" 2>/dev/null || true

      ${pkgs.postgresql_16}/bin/psql -d matrix-mas -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" 2>/dev/null || true
    '';
  };
}
