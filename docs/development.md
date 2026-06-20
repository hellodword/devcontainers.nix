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

The smoke runner never accepts extra Docker run arguments. It probes `docker info` on the host, forwards only a reachable `tcp://` `DOCKER_HOST` into the container for the daemon test, and skips that test otherwise.

## GitHub Actions

Image workflows are generated one file per image with `nix run .#generate-workflows`. The generator renders `.github/workflows/_build-image.yml.j2` with minijinja and writes complete `build-image-*.yml` workflows instead of using a local reusable workflow. This avoids intermittent `uses: ./.github/workflows/...` behavior in GitHub Actions.

One workflow per image is intentional: combining a matrix image build with workflow concurrency previously caused GitHub Actions to cancel every unfinished matrix job before the image set completed. Separate workflows give each image its own concurrency group, so a newer push cancels the older run for the same image regardless of ref. The top-level `build.yml` workflow is manual-only and takes an `image-target` input for ad-hoc image builds.

The workflows do not use GitHub Actions cache. Nix already uses configured binary substituters for reusable store paths, while the per-run image closures and Docker artifacts are large, highly input-sensitive, and expensive to upload and restore through Actions cache. Relying on fresh Nix evaluation plus substituters is simpler and avoids stale or partial cache state.

The `Free disk space` step removes large preinstalled SDKs that these images do not use, then prunes Docker state. Hosted Ubuntu runners have limited writable disk, and building nix2container images, copying OCI artifacts, loading them into Docker, and running smoke tests can otherwise fail with `ENOSPC`. The final `df -h` makes disk pressure visible in logs.
