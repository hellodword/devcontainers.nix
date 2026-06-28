# Documentation Index

Use this index to jump from intent to the right document or section.

## Use Published Images

| Intent                                                 | Go to                                                    |
| ------------------------------------------------------ | -------------------------------------------------------- |
| Start from a minimal `.devcontainer/devcontainer.json` | [Usage: Basic Devcontainer](usage.md#basic-devcontainer) |
| Pick a published image reference                       | [README: Quick Start](../README.md#quick-start)          |
| Understand fixed user and image defaults               | [Usage: Runtime Defaults](usage.md#runtime-defaults)     |
| Add project-specific CLI tools                         | [Usage: Packages](usage.md#packages)                     |

## Configure Editor Behavior

| Intent                                               | Go to                                                                                            |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Set VS Code settings in a project                    | [Usage: VS Code Settings](usage.md#vs-code-settings)                                             |
| Understand generated VS Code metadata and extensions | [Architecture: VS Code Metadata And Extensions](architecture.md#vs-code-metadata-and-extensions) |
| Maintain preinstalled extensions or editor defaults  | [Development: Adding A Language Or Runtime](development.md#adding-a-language-or-runtime)         |

## Add Runtime Or Native Dependencies

| Intent                                          | Go to                                                                                          |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Add packages after container creation           | [Usage: Packages](usage.md#packages)                                                           |
| Add shared libraries for FFI or runtime loaders | [Usage: Native Libraries And `LD_LIBRARY_PATH`](usage.md#native-libraries-and-ld_library_path) |
| Add build libraries such as OpenSSL             | [Usage: Native Libraries And `LD_LIBRARY_PATH`](usage.md#native-libraries-and-ld_library_path) |
| Understand library compiler behavior            | [Architecture: Native Libraries](architecture.md#native-libraries)                             |

## Run GUI Apps And Browsers

| Intent                                     | Go to                                                                                  |
| ------------------------------------------ | -------------------------------------------------------------------------------------- |
| Run Chromium or browser automation         | [Usage: Chromium And Browser Automation](usage.md#chromium-and-browser-automation)     |
| Tune `/dev/shm` for Chromium               | [Chromium In Dev Containers: `/dev/shm` Size](chromium.md#devshm-size)                 |
| Understand browser sandbox tradeoffs       | [Chromium In Dev Containers: Sandbox Failures](chromium.md#sandbox-failures)           |
| Keep the retained SUID sandbox pitfall log | [Chromium In Dev Containers: SUID Sandbox Pitfalls](chromium.md#suid-sandbox-pitfalls) |
| Debug GUI forwarding                       | [GUI Forwarding: Debugging](gui-forwarding.md#debugging)                               |
| Understand startup ordering pitfalls       | [GUI Forwarding: Startup Ordering Pitfall](gui-forwarding.md#startup-ordering-pitfall) |

## Use Runtime Isolation Or Docker

| Intent                                               | Go to                             |
| ---------------------------------------------------- | --------------------------------- |
| Start a devcontainer with the gVisor runtime         | [Usage: gVisor](usage.md#gvisor)  |
| Connect to an external Docker daemon                 | [Remote Docker](docker-remote.md) |
| Understand why the images do not start Docker daemon | [Remote Docker](docker-remote.md) |

## Maintain This Repository

| Intent                                  | Go to                                                                                    |
| --------------------------------------- | ---------------------------------------------------------------------------------------- |
| Understand the compiler design          | [Architecture](architecture.md)                                                          |
| Decide where new content belongs        | [Development: Placement Decision Guide](development.md#placement-decision-guide)         |
| Make small edits to an existing module  | [Development: Small Existing Module Edits](development.md#small-existing-module-edits)   |
| Add or change an image target           | [Development: Adding Or Changing An Image](development.md#adding-or-changing-an-image)   |
| Add a language profile                  | [Development: Adding A Language Or Runtime](development.md#adding-a-language-or-runtime) |
| Run smoke checks and reports            | [Development: Smoke Tests](development.md#smoke-tests)                                   |
| Run heavy VS Code GUI E2E tests         | [VS Code GUI E2E Testing](e2e-testing.md)                                                |
| Update generated documentation snippets | [Development: Documentation Rules](development.md#documentation-rules)                   |
