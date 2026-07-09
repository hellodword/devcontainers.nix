# Testing Architecture

This repository tests a Nix devcontainer image compiler. Keep product facts near
the Nix owner that defines them, and keep Python at imperative boundaries where
it has a clear job.

The goal is maintainability, not a no-Python policy. A test is in the right
place when the next maintainer can change one product fact and find the matching
assertion next to the owner, compiler stage, target registry, or focused
contract.

## Ownership Model

Use these layers in order:

| Layer                 | Owns                                                                                                                          | Good assertions                                                                              |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Nix owner module      | Packages, profiles, environment, VS Code metadata, libraries, lifecycle tasks, smoke cases, and layer buckets for one feature | The owner exposes the expected structured data                                               |
| Image target registry | Image identity, family/tag policy, E2E opt-in, and target-specific required profiles, commands, or rootfs paths               | Target contracts such as required commands for `go`                                          |
| Compiler stage        | Derived artifact structure and report shape                                                                                   | Compiler output contains normalized attrs and expected report entries                        |
| Nix contract check    | Cross-owner product rules over structured attrs                                                                               | Profiles resolve to smoke cases, required target commands exist, security checks are enabled |
| Python artifact check | JSON, filesystem, tar, Docker, process, or GUI boundaries                                                                     | A report bundle is complete, an OCI image JSON is parseable, rootfs paths exist              |
| Smoke runner          | Runtime command behavior inside a loaded container                                                                            | Declared cases run in Docker with stable scripts and timeouts                                |
| GUI E2E               | Heavy VS Code Dev Containers behavior                                                                                         | Opt-in editor session behavior only                                                          |

Do not add a second owner list in a check module when a compiler or registry
already publishes the same information. For example, `ci-plan.json` is derived
from `lib/compiler/reports.nix`, so report bundle checks should read the plan
instead of keeping another required-file list.

## Python Boundary

Python is appropriate for checks that need:

- JSON parsing and structured error messages;
- filesystem traversal and path normalization;
- OCI image JSON or tar inspection;
- subprocess orchestration;
- Docker smoke execution;
- GUI automation boundaries;
- small reusable parsing helpers, such as layer budget parsing.

Python should not own product facts such as:

- default locale values;
- language aliases;
- expected VS Code extension identities;
- profile ownership;
- layer bucket policy;
- target required commands;
- target required profiles;
- smoke case identity.

When Python needs expected data, generate that data from Nix and pass it as an
input file or argument. The script should validate the artifact against the
expected data, not reconstruct the product policy internally.

## Nix Contracts

Use focused contracts under `flake/checks/contracts/` for product assertions
that can be checked from evaluated Nix attrs. A good contract reads like a
small policy check over already-structured data.

Prefer Nix contracts for:

- profile inclusion and ownership rules;
- target-specific required profiles and commands;
- layer bucket membership and ordering policy;
- environment and PATH shape derived by the compiler;
- metadata and VS Code extension projections;
- compiler-generated security check structure;
- smoke plan identity derived from `devcontainer.tests.cases`;
- report entries that are already declared in Nix.

Keep helper functions mechanical. A helper may compare sets, find an item by
id, emit JSON for a check script, or build one derivation per image. It should
not hide product policy or contain image-specific facts.

## Artifact Checks

Artifact checks prove that real build outputs match the structured plan:

- `check-image-tar.py` should inspect the built image artifact and compare it
  with expected data from Nix.
- `check-rootfs-layout.py` should inspect the rootfs and compare it with
  filesystem reports or target policy from Nix.
- report bundle checks should verify that `ci-plan.json` is valid, listed files
  exist, listed JSON parses, and there are no unexpected unregistered report
  JSON files.
- report CLI checks should keep black-box coverage for user-facing
  `devcontainer-image` commands.

Artifact checks should not duplicate product contracts that can be evaluated
before building rootfs or image artifacts.

## Smoke Coverage

Use `devcontainer.tests.cases` as the preferred source for runtime smoke
coverage. Put the case next to the profile, module, or owner that exposes the
user-visible behavior.

Example:

```nix
tests.cases."language.example" = {
  tags = [
    "smoke"
    "language"
    "example"
  ];
  scripts = [
    {
      shell = "bash";
      interactive = false;
      command = "example-tool --version";
    }
  ];
};
```

Use a smoke case when the behavior must run in a real container: commands,
shell initialization, generated files, environment lookup, dynamic libraries,
or runtime helper behavior.

Do not add top-level smoke cases from non-core modules. For a bundle-only
behavior, add a zero-package smoke-only leaf profile and include that profile
from the bundle.

## Migration Checklist

When adding or changing behavior:

1. Identify the owner: module, compiler stage, target registry, runtime helper,
   or GUI E2E registry.
2. Put product facts in the owner or the compiler output, not in a Python
   assertion script.
3. Add or update a Nix contract when the rule can be checked from evaluated
   attrs.
4. Add or update a Python artifact check only when the real filesystem, image
   JSON, subprocess, Docker, or GUI boundary matters.
5. Add or update `devcontainer.tests.cases` when user-visible runtime behavior
   should execute in a loaded container.
6. Keep report CLI checks when a report becomes user-facing through
   `devcontainer-image explain`, `diff`, or `doctor`.
7. Run the narrow check for the touched boundary before running broader flake
   checks.

## Bad Smells

Move or redesign the check when you see:

- one long script mixing bundle completeness, product policy, security,
  filesystem layout, profile ownership, smoke case identity, and artifact
  parsing;
- a Python constant that names default product behavior owned by a Nix module;
- a separate required report list that duplicates `compileReports`;
- a grep-only negative check for a behavior that has structured data;
- a check that parses generated JSON to rediscover data already available as
  compiler attrs;
- duplicate smoke schema validation outside the smoke runner or one focused
  input contract;
- a compatibility shim for internal report JSON with no external consumer.

## Validation Choices

Use the smallest check that proves the changed boundary:

| Change                        | First validation                                        |
| ----------------------------- | ------------------------------------------------------- |
| Documentation only            | `nix flake show --no-write-lock-file`                   |
| Nix contract helper           | A focused contract build                                |
| Product contract over reports | `nix build .#checks.x86_64-linux.contracts-reports-all` |
| Image artifact checker        | `nix build .#checks.x86_64-linux.artifact-image-nix`    |
| Rootfs artifact checker       | `nix build .#checks.x86_64-linux.artifact-rootfs-nix`   |
| Python script quality         | `nix build .#checks.x86_64-linux.script-quality`        |
| Public helper behavior        | The matching `tool-*` check                             |
| Cross-cutting cleanup         | `nix flake check`                                       |

Do not make GUI E2E part of the default check path. Use
[VS Code GUI E2E Testing](e2e-testing.md) for those opt-in sessions.
