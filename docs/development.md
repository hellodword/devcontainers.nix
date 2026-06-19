# Development

Run the static and evaluation checks:

```sh
nix flake check
```

Build reports for one image:

```sh
nix build .#images.nix-latest.reports
```

Build the nix2container image artifact:

```sh
nix build .#images.nix-latest.oci
```

Load an image into Docker:

```sh
nix run .#load-nix-latest
nix run .#load-python3
```

Run smoke tests after loading:

```sh
tests/smoke/run-plan.sh nix-latest
```

Validate remote Docker CLI behavior with a reachable TCP daemon:

```sh
DOCKER_HOST=tcp://172.17.0.1:2375 tests/smoke/run-plan.sh nix-latest
```

For release smoke where Docker daemon access is mandatory:

```sh
SMOKE_REQUIRE_DOCKER_DAEMON=1 DOCKER_HOST=tcp://172.17.0.1:2375 tests/smoke/run-plan.sh nix-latest
```

Collect runtime evidence:

```sh
tests/smoke/collect-runtime-evidence.sh oci nix-latest
tests/smoke/collect-runtime-evidence.sh full
```

The smoke runner never accepts extra Docker run arguments. It probes `docker info` on the host, forwards only a reachable `tcp://` Docker environment into the container for the daemon test, and skips that test otherwise.
