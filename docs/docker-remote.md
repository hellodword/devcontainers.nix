# Remote Docker

The images ship Docker client tools only. They do not configure a daemon endpoint, mount a socket, or start a daemon.

Set `DOCKER_HOST` in Dev Containers metadata when a project needs to use a host or remote daemon:

```json
{
  "containerEnv": {
    "DOCKER_HOST": "tcp://172.17.0.1:2375"
  }
}
```

`tcp://172.17.0.1:2375` is a high-privilege Docker API. Any process that can reach it can usually build images, start privileged containers, mount host paths, and effectively control the host. Use it only for trusted local development or controlled CI environments.

For cross-machine access, use TLS, SSH forwarding, a secure proxy, or a managed Docker endpoint with authentication and network policy. Do not expose an unauthenticated Docker TCP socket on a shared or public network.

Smoke tests read only the current environment:

- `DOCKER_HOST`
- `DOCKER_TLS_VERIFY`
- `DOCKER_CERT_PATH`

When `DOCKER_HOST` is a reachable `tcp://...` endpoint, `tests/smoke/run-plan.sh` passes those variables into the container for the Docker daemon smoke test. Without a reachable TCP endpoint, that specific test is skipped unless `SMOKE_REQUIRE_DOCKER_DAEMON=1` is set.
