{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/notesnook";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  quadlets = {
    networks.notesnook.networkConfig.driver = "bridge";

    pods.notesnook = { };

    containers = {
      notesnook-db = {
        containerConfig = {
          image = "docker.io/mongo:7.0.12";
          name = "notesnook-db";
          volumes = [
            "${CONTAINER_PATH}/db:/data/db"
          ];
          exec = "--replSet rs0 --bind_ip_all";
          healthCmd = "echo 'try { rs.status() } catch (err) { rs.initiate() }; db.runCommand(''\"ping''\").ok' | mongosh mongodb://localhost:27017 --quiet";
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      notesnook-s3 = {
        containerConfig = {
          image = "docker.io/minio/minio:RELEASE.2024-07-29T22-14-52Z";
          name = "notesnook-s3";
          environments = {
            MINIO_BROWSER = "on";
          };
          environmentFiles = [ osConfig.sops.secrets.notesnook_env.path ];
          volumes = [
            "${CONTAINER_PATH}/s3:/data/s3"
          ];
          publishPorts = [
            "${toString osConfig.ports.notesnook-s3}:9000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=notes-s3.kuck.ing"
            "blackbox.disabled=true"
          ];
          exec = "server /data/s3 --console-address :9090";
          healthCmd = "timeout 5s bash -c ':> /dev/tcp/127.0.0.1/9000' || exit 1";
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      notesnook-s3-setup = {
        containerConfig = {
          image = "docker.io/minio/mc:RELEASE.2024-07-26T13-08-44Z";
          name = "notesnook-s3-setup";
          environmentFiles = [ osConfig.sops.secrets.notesnook_env.path ];
          entrypoint = "/bin/bash";
          exec = [
            "-c"
            ''
              until mc alias set minio http://notesnook-s3:9000 $${MINIO_ROOT_USER} $${MINIO_ROOT_PASSWORD}; do
                sleep 1;
              done;
              mc mb minio/attachments -p
            ''
          ];
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        unitConfig = {
          Requires = [ containers.notesnook-s3.ref ];
          After = [ containers.notesnook-s3.ref ];
        };
      };

      notesnook-identity-server = {
        containerConfig = {
          image = "docker.io/streetwriters/identity:latest";
          name = "notesnook-identity-server";
          publishPorts = [
            "${toString osConfig.ports.notesnook-identity}:8264"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=notes-identity.kuck.ing"
            "blackbox.path=/health"
          ];
          environments = {
            MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/identity?replSet=rs0";
            MONGODB_DATABASE_NAME = "identity";
          };
          environmentFiles = [ osConfig.sops.secrets.notesnook_env.path ];
          healthCmd = "wget --tries=1 -nv -q  http://localhost:8264/health -O- || exit 1";
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        unitConfig = {
          Requires = [ containers.notesnook-db.ref ];
          After = [ containers.notesnook-db.ref ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      notesnook-server = {
        containerConfig = {
          image = "docker.io/streetwriters/notesnook-sync:latest";
          name = "notesnook-server";
          publishPorts = [
            "${toString osConfig.ports.notesnook-server}:5264"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=notes-sync.kuck.ing"
            "blackbox.path=/health"
          ];
          environments = {
            MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/?replSet=rs0";
            MONGODB_DATABASE_NAME = "notesnook";
            S3_INTERNAL_SERVICE_URL = "http://notesnook-s3:9000";
            S3_INTERNAL_BUCKET_NAME = "attachments";
            S3_SERVICE_URL = "https://notes-s3.kuck.ing";
            S3_REGION = "us-east-1";
            S3_BUCKET_NAME = "attachments";
          };
          environmentFiles = [ osConfig.sops.secrets.notesnook_env.path ];
          healthCmd = "wget --tries=1 -nv -q  http://localhost:5264/health -O- || exit 1";
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        unitConfig = {
          Requires = [
            containers.notesnook-s3.ref
            containers.notesnook-s3-setup.ref
            containers.notesnook-identity-server.ref
          ];
          After = [
            containers.notesnook-s3.ref
            containers.notesnook-s3-setup.ref
            containers.notesnook-identity-server.ref
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      notesnook-sse-server = {
        containerConfig = {
          image = "docker.io/streetwriters/sse:latest";
          name = "notesnook-sse";
          publishPorts = [
            "${toString osConfig.ports.notesnook-sse}:7264"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=notes-sse.kuck.ing"
            "blackbox.path=/health"
          ];
          environments = {
            MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/?replSet=rs0";
            MONGODB_DATABASE_NAME = "notesnook";
            S3_INTERNAL_SERVICE_URL = "http://notesnook-s3:9000";
            S3_INTERNAL_BUCKET_NAME = "attachments";
            S3_SERVICE_URL = "https://notes-s3.kuck.ing";
            S3_REGION = "us-east-1";
            S3_BUCKET_NAME = "attachments";
          };
          environmentFiles = [ osConfig.sops.secrets.notesnook_env.path ];
          healthCmd = "wget --tries=1 -nv -q  http://localhost:7264/health -O- || exit 1";
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        unitConfig = {
          Requires = [
            containers.notesnook-identity-server.ref
            containers.notesnook-server.ref
          ];
          After = [
            containers.notesnook-identity-server.ref
            containers.notesnook-server.ref
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      notesnook-monograph-server = {
        containerConfig = {
          image = "docker.io/streetwriters/monograph:latest";
          name = "notesnook-monograph-server";
          publishPorts = [
            "${toString osConfig.ports.notesnook-monograph}:3000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=notes-monograph.kuck.ing"
            "blackbox.path=/health"
          ];
          environments = {
            API_HOST = "http://notesnook-server:5264";
            PUBLIC_URL = "https://notes-monograph.kuck.ing";
            NODE_ENV = "production";
            HOST = "0.0.0.0";
          };
          environmentFiles = [ osConfig.sops.secrets.notesnook_env.path ];
          healthCmd = "timeout 5s bash -c ':> /dev/tcp/127.0.0.1/3000' || exit 1";
          networks = [ networks.notesnook.ref ];
          pod = pods.notesnook.ref;
        };
        unitConfig = {
          Requires = [
            containers.notesnook-server.ref
          ];
          After = [
            containers.notesnook-server.ref
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
