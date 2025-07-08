#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: with ps; [ prometheus-client packaging ])"


import argparse
import os
import time
from collections.abc import Iterator
from pathlib import Path
from prometheus_client import CollectorRegistry, start_http_server
from prometheus_client.core import GaugeMetricFamily, Metric
from pystemd.dbuslib import DBus
from pystemd.systemd1 import Unit
from SystemdUnitParser import SystemdUnitParser


class QuadletSystemCollector:
    def collect(self) -> Iterator[Metric]:
        quadlet_dir = Path.home() / ".config" / "containers" / "systemd"
        quadlet_containers = self.create_gauge_family(
            "quadlet_container_status",
            "Whether or not a container belongs to a quadlet",
        )
        quadlet_networks = self.create_gauge_family(
            "quadlet_network_status",
            "Whether or not a network belongs to a quadlet",
        )
        quadlet_pods = self.create_gauge_family(
            "quadlet_pod_status",
            "Whether or not a pod belongs to a quadlet",
        )

        with DBus(user_mode=True) as bus:
            for file in os.listdir(quadlet_dir):
                file_stem = Path(file).stem

                config = SystemdUnitParser()
                config.read(os.path.join(quadlet_dir, file))

                if file.endswith(".container"):
                    object_name = config.get("Container", "ContainerName")
                    service_name = f"{file_stem}.service"
                    metric_family = quadlet_containers
                elif file.endswith(".network"):
                    object_name = config.get("Network", "NetworkName")
                    service_name = f"{file_stem}-network.service"
                    metric_family = quadlet_networks
                elif file.endswith(".pod"):
                    object_name = config.get("Pod", "PodName")
                    service_name = f"{file_stem}-pod.service"
                    metric_family = quadlet_pods
                else:
                    continue

                unit = Unit(service_name.encode("UTF-8"), bus=bus)
                unit.load()
                state = unit.Unit.ActiveState.decode("utf-8")
                sub_state = unit.Unit.SubState.decode("utf-8")
                result = unit.Service.Result.decode("utf-8")

                metric_family.add_metric(
                    [object_name, service_name, state, sub_state, result], 1
                )

        yield quadlet_containers
        yield quadlet_networks
        yield quadlet_pods

    def create_gauge_family(self, name: str, description: str) -> GaugeMetricFamily:
        return GaugeMetricFamily(
            name,
            description,
            labels=["name", "service_name", "state", "sub_state", "result"],
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    registry = CollectorRegistry()
    registry.register(QuadletSystemCollector())

    # Start up the server to expose the metrics.
    start_http_server(args.port, registry=registry)

    while True:
        time.sleep(100000)


if __name__ == "__main__":
    main()
