# Remote Docker

The images ship Docker client tools only. They do not configure a daemon endpoint, mount a socket, or start a daemon.

This is a security design. A Docker daemon is a high-privilege control plane: access to it usually means the caller can build images, start privileged containers, mount host paths, and control the host that runs the daemon. For that reason, the daemon should live outside the devcontainer in a virtual machine or another isolated environment with its own security boundary.

The devcontainer should be treated as a client of that isolated daemon, not as the place where the daemon runs. This keeps normal editor and build tools separate from the service that can create privileged containers. It also makes the trust boundary explicit: project code can use Docker only when the project chooses to point the client at a daemon endpoint.

Set `DOCKER_HOST` in Dev Containers metadata when a project needs to use a host or remote daemon:

```json
{
  "containerEnv": {
    "DOCKER_HOST": "tcp://172.17.0.1:2375"
  }
}
```

`tcp://172.17.0.1:2375` is a high-privilege Docker API. Any process that can reach it can usually build images, start privileged containers, mount host paths, and effectively control the host. Use it only for trusted local development or controlled CI environments.

For cross-machine access, use SSH forwarding, a secure proxy, or a managed Docker endpoint with authentication and network policy. Do not expose an unauthenticated Docker TCP socket on a shared or public network. Prefer a daemon endpoint inside a disposable VM, development VM, or other isolated host over a daemon that directly controls your workstation or production host.

Smoke tests read only `DOCKER_HOST` from the current environment.

When `DOCKER_HOST` is a reachable `tcp://...` endpoint, `tests/smoke/run-plan.sh` passes that variable into the container for the Docker daemon smoke test. Without a reachable TCP endpoint, that specific test is skipped unless `SMOKE_REQUIRE_DOCKER_DAEMON=1` is set.
