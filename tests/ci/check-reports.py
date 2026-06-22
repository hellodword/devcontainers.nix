#!/usr/bin/env python3
import json
import os
import pathlib
import re
import subprocess
import sys

REQUIRED_REPORT_FILES = {
    "ci-plan.json",
    "closure-report.json",
    "env-report.json",
    "extensions-index.json",
    "extensions-report.json",
    "filesystem-report.json",
    "fhs-runtime-report.json",
    "fontconfig-report.json",
    "graph.json",
    "image-plan.json",
    "layer-plan.json",
    "libraries-report.json",
    "metadata-label.json",
    "metadata-merged-preview.json",
    "metadata-schema-report.json",
    "profile-report.json",
    "security-report.json",
    "shell-report.json",
    "smoke-test-plan.json",
}

REQUIRED_CI_REPORT_FILES = REQUIRED_REPORT_FILES - {"ci-plan.json"}
SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)
SIZE_BUDGET_RE = re.compile(r"^\s*\d+(?:\.\d+)?\s*(?:[kmgt]?i?b?|b)?\s*$", re.IGNORECASE)


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def fail(message: str):
    print(f"report-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-reports.py <reports-dir> <image-name>", file=sys.stderr)
        return 1

    reports_dir = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    missing_reports = sorted(
        report_name for report_name in REQUIRED_REPORT_FILES if not (reports_dir / report_name).is_file()
    )
    if missing_reports:
        fail(f"reports directory missing files: {', '.join(missing_reports)}")

    metadata_label = read_json(reports_dir / "metadata-label.json")
    metadata_preview = read_json(reports_dir / "metadata-merged-preview.json")
    metadata_schema = read_json(reports_dir / "metadata-schema-report.json")
    profile_report = read_json(reports_dir / "profile-report.json")
    layer_plan = read_json(reports_dir / "layer-plan.json")
    extensions_report = read_json(reports_dir / "extensions-report.json")
    extensions_index = read_json(reports_dir / "extensions-index.json")
    filesystem_report = read_json(reports_dir / "filesystem-report.json")
    smoke_plan = read_json(reports_dir / "smoke-test-plan.json")
    image_plan = read_json(reports_dir / "image-plan.json")
    security_report = read_json(reports_dir / "security-report.json")
    fhs_runtime_report = read_json(reports_dir / "fhs-runtime-report.json")
    fontconfig_report = read_json(reports_dir / "fontconfig-report.json")
    ci_plan = read_json(reports_dir / "ci-plan.json")
    env_report = read_json(reports_dir / "env-report.json")
    libraries_report = read_json(reports_dir / "libraries-report.json")
    shell_report = read_json(reports_dir / "shell-report.json")
    preview_container_env = metadata_preview.get("containerEnv") or {}
    environment_report = env_report.get("environment") or {}
    enabled_profile_ids = {profile["id"] for profile in profile_report.get("enabledProfiles") or []}
    profile_package_names = set(profile_report.get("packages") or [])
    provided_commands = set((profile_report.get("provides") or {}).get("commands") or [])
    profile_extension_ids = set((profile_report.get("vscode") or {}).get("extensionIds") or [])
    profile_vscode_settings = (profile_report.get("vscode") or {}).get("settings") or {}
    profile_library_presets = set((profile_report.get("libraries") or {}).get("presets") or [])

    if not isinstance(metadata_label, list):
        fail("metadata-label.json must be a JSON array")
    if not metadata_schema["hasRemoteUser"]:
        fail("metadata schema must include remoteUser")
    if not metadata_schema["hasLifecycle"]:
        fail("metadata schema must include lifecycle commands")
    if not metadata_schema["hasVscodeCustomizations"]:
        fail("metadata schema must include VS Code customizations")
    if metadata_schema["hasDockerMetadata"]:
        fail(f"{image_name} metadata must not declare Docker daemon access metadata")
    if metadata_preview.get("remoteUser") != "vscode":
        fail("metadata merged preview must keep remoteUser as vscode")
    if metadata_preview.get("containerUser") != "vscode":
        fail("metadata merged preview must keep containerUser as vscode")
    if metadata_preview.get("updateRemoteUserUID") is not False:
        fail("metadata merged preview must disable updateRemoteUserUID")

    for report_name in REQUIRED_REPORT_FILES:
        report_data = read_json(reports_dir / report_name)
        for text in walk_strings(report_data):
            if SENSITIVE_VALUE_RE.search(text):
                fail(f"{report_name} appears to contain sensitive material")

    layer_count = len(layer_plan["layers"])
    layer_max = int(layer_plan["budget"]["max"])
    max_layer_size = layer_plan["budget"].get("maxLayerSize")
    if not isinstance(max_layer_size, str) or not SIZE_BUDGET_RE.match(max_layer_size):
        fail("layer-plan.json budget must include maxLayerSize, for example 8GiB")
    if layer_count > layer_max:
        fail(f"layer count {layer_count} exceeds budget {layer_max}")
    for layer in layer_plan["layers"]:
        if not layer["build"]["copyToRoot"]:
            fail(f"layer {layer['group']} must be buildable as a copyToRoot layer")
        if layer["pathCount"] < 1:
            fail(f"layer {layer['group']} must include at least one store path")
        paths_to_link = layer["build"].get("pathsToLink") or []
        for required_link in ["/bin", "/lib", "/libexec", "/share", "/etc"]:
            if required_link not in paths_to_link:
                fail(f"layer {layer['group']} missing pathsToLink entry: {required_link}")
        if not isinstance(layer["build"].get("extraOutputsToInstall"), list):
            fail(f"layer {layer['group']} must report extraOutputsToInstall as a list")
    font_layers = [layer for layer in layer_plan["layers"] if layer["group"] == "02-fonts-runtime"]
    if len(font_layers) != 1:
        fail("layer-plan.json must include one 02-fonts-runtime layer")
    if "runtime/fonts" not in font_layers[0]["members"]:
        fail("02-fonts-runtime layer must include runtime/fonts")
    profile_ids_with_packages = {
        profile["id"]
        for profile in profile_report.get("enabledProfiles") or []
        if profile.get("packageCount", 0) > 0
    }
    layer_members = {member for layer in layer_plan["layers"] for member in layer.get("members", [])}
    missing_profile_layers = sorted(profile_ids_with_packages - layer_members)
    if missing_profile_layers:
        fail(f"layer-plan.json missing enabled package profiles: {', '.join(missing_profile_layers)}")

    if not smoke_plan["tests"]:
        fail("smoke-test-plan.json must include at least one test")
    smoke_ids = {test.get("id") for test in smoke_plan["tests"]}
    if len(smoke_ids) != len(smoke_plan["tests"]):
        fail("smoke-test-plan.json must not contain duplicate ids")
    for test in smoke_plan["tests"]:
        test_id = test.get("id")
        if not isinstance(test_id, str) or not test_id:
            fail("smoke-test-plan.json entries must include id")
        if not isinstance(test.get("tags"), list) or not all(isinstance(tag, str) and tag for tag in test["tags"]):
            fail(f"smoke test {test_id} must include string tags")
        if "smoke" not in test["tags"]:
            fail(f"smoke test {test_id} must include the smoke tag")
        if not isinstance(test.get("command"), list) or not all(
            isinstance(part, str) and part for part in test["command"]
        ):
            fail(f"smoke test {test_id} must include a command array")
        if not isinstance(test.get("requires"), list) or not all(
            isinstance(requirement, str) and requirement for requirement in test["requires"]
        ):
            fail(f"smoke test {test_id} must include requires")
        if not isinstance(test.get("timeoutSeconds"), int) or test["timeoutSeconds"] < 1:
            fail(f"smoke test {test_id} must include timeoutSeconds")
    declared_capabilities = set((profile_report.get("tests") or {}).get("declaredCapabilities") or [])
    missing_declared_capabilities = sorted(declared_capabilities - smoke_ids)
    if missing_declared_capabilities:
        fail(f"smoke-test-plan.json missing declared capabilities: {', '.join(missing_declared_capabilities)}")
    if image_plan.get("smokeTestCount") != len(smoke_plan["tests"]):
        fail("image-plan.json smokeTestCount must match smoke-test-plan.json")
    if image_name == "nix":
        required_profiles = {"runtime/python", "language/python", "runtime/nodejs"}
        missing_profiles = sorted(required_profiles - enabled_profile_ids)
        if missing_profiles:
            fail(f"nix image missing required profiles: {', '.join(missing_profiles)}")
        required_commands = {"python", "python3", "pip", "pip3", "uv", "uvx", "node", "npm", "npx", "corepack"}
        missing_commands = sorted(required_commands - provided_commands)
        if missing_commands:
            fail(f"nix image missing required runtime commands: {', '.join(missing_commands)}")

    smoke_plan_file = reports_dir / "smoke-test-plan.json"
    smoke_checker = pathlib.Path(
        os.environ.get("CHECK_SMOKE_PLAN", pathlib.Path(__file__).with_name("check-smoke-plan.py"))
    )
    subprocess.run(
        ["python3", str(smoke_checker), str(smoke_plan_file), str(reports_dir / "profile-report.json"), image_name],
        check=True,
    )

    if image_plan["backend"] != "nix2container":
        fail("image-plan.json must report nix2container backend")
    if image_plan["entrypoint"] != ["/usr/bin/devcontainer-entrypoint"]:
        fail("image-plan.json entrypoint mismatch")
    if image_plan["user"] != "vscode":
        fail("image-plan.json must run as vscode")
    if image_plan["workingDir"] != "/workspaces":
        fail("image-plan.json working directory mismatch")
    closure_packages = set((read_json(reports_dir / "closure-report.json")).get("packages") or [])
    missing_profile_packages = sorted(profile_package_names - closure_packages)
    if missing_profile_packages:
        fail(f"closure-report.json missing profile packages: {', '.join(missing_profile_packages)}")

    if not fhs_runtime_report["enabled"]:
        fail("fhs-runtime-report.json must confirm FHS runtime is enabled")
    if fhs_runtime_report.get("dynamicLoaderMode") != "nix-ld":
        fail("fhs-runtime-report.json must confirm nix-ld dynamic loader mode")
    real_glibc_loader = fhs_runtime_report.get("realGlibcLoader")
    if not real_glibc_loader or "glibc" not in real_glibc_loader:
        fail("fhs-runtime-report.json must report the real glibc loader")
    if real_glibc_loader == "/lib64/ld-linux-x86-64.so.2":
        fail("NIX_LD must point at the real glibc loader, not the container interpreter")
    fhs_links = {link["target"]: link["source"] for link in fhs_runtime_report["symlinks"]}
    for required_link in [
        "/lib64/ld-linux-x86-64.so.2",
        "/usr/lib/libc.so.6",
        "/usr/lib/libstdc++.so.6",
    ]:
        if required_link not in fhs_links:
            fail(f"fhs-runtime-report.json missing VS Code runtime link: {required_link}")
    ca_certificates = fhs_runtime_report.get("caCertificates") or {}
    if ca_certificates.get("bundle") != "/etc/ssl/certs/ca-certificates.crt":
        fail("fhs-runtime-report.json must report the CA bundle path")
    if "ca-certificates" not in ca_certificates.get("root", ""):
        fail("CA certificates must come from dockerTools.caCertificates")
    if not ca_certificates.get("source", "").endswith("/etc/ssl/certs/ca-certificates.crt"):
        fail("CA certificate source must point at the dockerTools bundle")
    if "glibc" not in fhs_links["/usr/lib/libc.so.6"]:
        fail("libc.so.6 must come from glibc")
    if "gcc" not in fhs_links["/usr/lib/libstdc++.so.6"]:
        fail("libstdc++.so.6 must come from the GCC runtime")
    if "nix-ld" not in fhs_links["/lib64/ld-linux-x86-64.so.2"]:
        fail("container dynamic loader must enter nix-ld")

    if "PATH" not in env_report["containerEnvSources"]:
        fail("env-report.json must include PATH source details")
    if not environment_report:
        fail("env-report.json must include the compiled environment namespace report")
    for required_link in ["/bin", "/include", "/lib", "/lib64", "/libexec", "/share", "/etc"]:
        if required_link not in environment_report.get("pathsToLink", []):
            fail(f"environment report missing pathsToLink entry: {required_link}")
    if not isinstance(environment_report.get("extraOutputsToInstall"), list):
        fail("environment report must include extraOutputsToInstall")
    if "EDITOR" not in environment_report.get("variables", {}):
        fail("environment report must include configured variables")
    reported_etc_paths = {entry.get("path") for entry in environment_report.get("etc", [])}
    for required_etc in [
        "/etc/nix/nix.conf",
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/localtime",
        "/etc/zoneinfo",
        "/etc/gitconfig",
        "/etc/ssh/ssh_config",
        "/etc/ssh/ssh_known_hosts",
    ]:
        if required_etc not in reported_etc_paths:
            fail(f"environment report missing generated etc file: {required_etc}")
    if not env_report["containerEnvSources"]["PATH"]["pathEntries"]:
        fail("env-report.json PATH source details must include path entries")
    if not env_report["containerEnvSources"]["EDITOR"]["sources"]:
        fail("env-report.json must include source labels for container env entries")
    if "PATH" in preview_container_env:
        fail("metadata merged preview must not publish PATH by default")
    if preview_container_env.get("EDITOR") != env_report["containerEnv"]["EDITOR"]:
        fail("metadata merged preview must retain the compiled EDITOR entry")
    if "LD_LIBRARY_PATH" in env_report["containerEnv"]:
        fail("container env must not export LD_LIBRARY_PATH by default")
    if "FONTCONFIG_FILE" in env_report["containerEnv"]:
        fail("container env must not set FONTCONFIG_FILE globally")
    expected_locale_env = {
        "LANG": "en_US.UTF-8",
        "LANGUAGE": "en_US:en",
        "XDG_CONFIG_DIRS": "/etc/xdg",
        "XDG_DATA_DIRS": "/usr/local/share:/usr/share",
    }
    for env_name, expected_value in expected_locale_env.items():
        if env_report["containerEnv"].get(env_name) != expected_value:
            fail(f"container env must set {env_name} to {expected_value}")
        if "core.locale" not in env_report["containerEnvSources"].get(env_name, {}).get("sources", []):
            fail(f"{env_name} must be sourced from core.locale")
    locale_archive = env_report["containerEnv"].get("LOCALE_ARCHIVE")
    if not locale_archive or "glibc-locales" not in locale_archive or not locale_archive.endswith("/lib/locale/locale-archive"):
        fail("container env must set LOCALE_ARCHIVE to the glibcLocales locale archive")
    if "core.locale" not in env_report["containerEnvSources"].get("LOCALE_ARCHIVE", {}).get("sources", []):
        fail("LOCALE_ARCHIVE must be sourced from core.locale")
    if "LC_ALL" in env_report["containerEnv"]:
        fail("container env must not set LC_ALL by default")
    if env_report["containerEnv"].get("TZDIR") != "/etc/zoneinfo":
        fail("container env must set TZDIR for the generated zoneinfo tree")
    expected_xdg = {
        "XDG_CONFIG_HOME": "/home/vscode/.config",
        "XDG_CACHE_HOME": "/home/vscode/.cache",
        "XDG_DATA_HOME": "/home/vscode/.local/share",
        "XDG_STATE_HOME": "/home/vscode/.local/state",
        "XDG_RUNTIME_DIR": "/run/user/1000",
    }
    for env_name, expected_value in expected_xdg.items():
        if env_report["containerEnv"].get(env_name) != expected_value:
            fail(f"container env must expand {env_name} to {expected_value}")
    expected_nixpkgs_env = {
        "NIXPKGS_CONFIG": "/etc/nixpkgs/config.nix",
        "NIXPKGS_ALLOW_UNFREE": "1",
        "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM": "1",
        "NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE": "1",
    }
    for env_name, expected_value in expected_nixpkgs_env.items():
        if env_report["containerEnv"].get(env_name) != expected_value:
            fail(f"container env must set {env_name} to {expected_value}")
        if "core.env" not in env_report["containerEnvSources"].get(env_name, {}).get("sources", []):
            fail(f"{env_name} must be sourced from core.env")
    expected_compat_env = {
        "DO_NOT_TRACK": "true",
        "NIX_PAGER": "cat",
        "NIX_PATH": "nixpkgs=/usr/share/devcontainer/nixpkgs",
    }
    for env_name, expected_value in expected_compat_env.items():
        if env_report["containerEnv"].get(env_name) != expected_value:
            fail(f"container env must set {env_name} to {expected_value}")
        if "core.env" not in env_report["containerEnvSources"].get(env_name, {}).get("sources", []):
            fail(f"{env_name} must be sourced from core.env")
    devpkg_nixpkgs_ref = env_report["containerEnv"].get("DEVPKG_NIXPKGS_REF", "")
    if not re.fullmatch(r"path:/nix/store/[a-z0-9]{32}-source", devpkg_nixpkgs_ref):
        fail("container env must set DEVPKG_NIXPKGS_REF to the locked nixpkgs store source")
    if "core.env" not in env_report["containerEnvSources"].get("DEVPKG_NIXPKGS_REF", {}).get("sources", []):
        fail("DEVPKG_NIXPKGS_REF must be sourced from core.env")
    for env_name, env_value in env_report["containerEnv"].items():
        if isinstance(env_value, str) and ("$HOME" in env_value or "$XDG_" in env_value):
            fail(f"container env must not retain unexpanded HOME/XDG references in {env_name}")
    path_value = env_report["containerEnv"].get("PATH", "")
    if "$HOME" in path_value or "$XDG_" in path_value:
        fail("container PATH must not retain unexpanded HOME/XDG references")
    path_segments = path_value.split(":") if path_value else []
    if "/bin" in path_segments:
        fail("container PATH must not include the usr-merge compatibility /bin symlink")
    if "/usr/local/bin" not in path_segments or "/usr/bin" not in path_segments:
        fail("container PATH must include /usr/local/bin and /usr/bin")
    if path_segments.index("/usr/local/bin") > path_segments.index("/usr/bin"):
        fail("container PATH must prefer /usr/local/bin before /usr/bin")
    nix_ld_env = fhs_runtime_report.get("nixLdEnv") or {}
    if env_report["containerEnv"].get("NIX_LD") != real_glibc_loader:
        fail("container env must set NIX_LD to the real glibc loader")
    if preview_container_env.get("NIX_LD") != real_glibc_loader:
        fail("metadata merged preview must retain NIX_LD")
    if env_report["containerEnv"].get("NIX_LD_LIBRARY_PATH") != nix_ld_env.get("NIX_LD_LIBRARY_PATH"):
        fail("container env must retain the compiled NIX_LD_LIBRARY_PATH")
    nix_ld_library_path = env_report["containerEnv"].get("NIX_LD_LIBRARY_PATH", "")
    if "glibc" not in nix_ld_library_path or "gcc" not in nix_ld_library_path:
        fail("NIX_LD_LIBRARY_PATH must include glibc and GCC runtime libraries")
    expected_runtime_profile = "/home/vscode/.local/share/devpkg/runtime-libraries/profile"
    expected_build_profile = "/home/vscode/.local/share/devpkg/build-libraries/profile"
    if libraries_report["runtime"].get("dynamicProfile") != expected_runtime_profile:
        fail("libraries-report.json must expand the runtime library profile")
    if libraries_report["build"].get("dynamicProfile") != expected_build_profile:
        fail("libraries-report.json must expand the build library profile")
    library_presets = libraries_report.get("settings", {}).get("presets") or []
    if len(library_presets) != len(set(library_presets)):
        fail("libraries-report.json must report de-duplicated library presets")
    for profile_env, expected_profile in {
        "DEVPKG_RUNTIME_LIBRARY_PROFILE": expected_runtime_profile,
        "DEVPKG_BUILD_LIBRARY_PROFILE": expected_build_profile,
    }.items():
        if env_report["containerEnv"].get(profile_env) != expected_profile:
            fail(f"container env must expose {profile_env}")
    for required_entry in [
        f"{expected_runtime_profile}/lib",
        f"{expected_build_profile}/lib",
    ]:
        if required_entry not in nix_ld_library_path:
            fail("NIX_LD_LIBRARY_PATH must include dynamic library profile lib paths")
    for env_name in [
        "PKG_CONFIG_PATH",
        "CMAKE_PREFIX_PATH",
        "NIXPKGS_CMAKE_PREFIX_PATH",
        "CPATH",
        "LIBRARY_PATH",
        "NIX_CFLAGS_COMPILE",
        "NIX_LDFLAGS",
    ]:
        if env_name not in env_report["containerEnv"]:
            fail(f"container env must include library discovery variable {env_name}")
        if env_name not in env_report["containerEnvSources"]:
            fail(f"env-report.json must include source details for {env_name}")
        if "compiler.libraries.core" not in env_report["containerEnvSources"][env_name]["sources"]:
            fail(f"{env_name} must be sourced from the library compiler")
    if set(library_presets) != profile_library_presets:
        fail("libraries-report.json presets must match profile-report.json")
    has_go_profile = "language/go" in enabled_profile_ids
    has_rust_profile = "language/rust" in enabled_profile_ids
    if has_go_profile:
        if "cgo" not in library_presets:
            fail("language/go profile must enable the cgo library preset")
        for env_name in ["CGO_CFLAGS", "CGO_LDFLAGS"]:
            if env_name not in env_report["containerEnv"]:
                fail(f"language/go profile must expose {env_name}")
            if "compiler.libraries.preset.cgo" not in env_report["containerEnvSources"][env_name]["sources"]:
                fail(f"{env_name} must be sourced from the cgo library preset")
        gobuild_alias = shell_report.get("aliases", {}).get("gobuild-small")
        if not gobuild_alias:
            fail("language/go profile must include the gobuild-small shell alias")
        if gobuild_alias.get("command") != 'go build -trimpath -ldflags "-s -w -buildid="':
            fail("gobuild-small alias command mismatch")
        if "language/go" not in gobuild_alias.get("origins", []):
            fail("gobuild-small alias must be sourced from language/go")
    elif "cgo" in library_presets:
        fail("cgo library preset must only come from a profile that declares it")
    elif "gobuild-small" in shell_report.get("aliases", {}):
        fail("gobuild-small alias must only come from language/go")
    if has_rust_profile:
        if "rust-bindgen" not in library_presets:
            fail("language/rust profile must enable the rust-bindgen library preset")
        if "BINDGEN_EXTRA_CLANG_ARGS" not in env_report["containerEnv"]:
            fail("language/rust profile must expose BINDGEN_EXTRA_CLANG_ARGS")
        if (
            "compiler.libraries.preset.rust-bindgen"
            not in env_report["containerEnvSources"]["BINDGEN_EXTRA_CLANG_ARGS"]["sources"]
        ):
            fail("BINDGEN_EXTRA_CLANG_ARGS must be sourced from the rust-bindgen library preset")
    elif "rust-bindgen" in library_presets:
        fail("rust-bindgen library preset must only come from a profile that declares it")
    for env_name in ["NIX_LD", "NIX_LD_LIBRARY_PATH"]:
        if env_name not in env_report["containerEnvSources"]:
            fail(f"env-report.json must include {env_name} source details")
        if "compiler.fhs-runtime.nix-ld" not in env_report["containerEnvSources"][env_name]["sources"]:
            fail(f"{env_name} must be sourced from the FHS runtime compiler")
    for env_name in ["SSL_CERT_FILE", "NIX_SSL_CERT_FILE", "CURL_CA_BUNDLE", "GIT_SSL_CAINFO"]:
        if env_report["containerEnv"].get(env_name) != "/etc/ssl/certs/ca-certificates.crt":
            fail(f"container env must set {env_name} to the CA bundle")
        if "compiler.fhs-runtime.ca-certificates" not in env_report["containerEnvSources"][env_name]["sources"]:
            fail(f"{env_name} must be sourced from FHS CA certificates")

    if not fontconfig_report.get("enabled"):
        fail("fontconfig-report.json must confirm fonts are enabled")
    fontconfig_settings = fontconfig_report.get("fontconfig") or {}
    if not fontconfig_settings.get("enabled"):
        fail("fontconfig-report.json must confirm fontconfig is enabled")
    if fontconfig_settings.get("package") != "fontconfig":
        fail("fontconfig-report.json must report the fontconfig package")
    if fontconfig_settings.get("configPath") != "/etc/fonts/fonts.conf":
        fail("fontconfig-report.json must report /etc/fonts/fonts.conf")
    if fontconfig_settings.get("confDir") != "/etc/fonts/conf.d":
        fail("fontconfig-report.json must report /etc/fonts/conf.d")
    reported_font_packages = {entry.get("name") for entry in fontconfig_report.get("packages", [])}
    for required_package in [
        "noto-fonts",
        "noto-fonts-cjk-sans",
        "noto-fonts-cjk-serif",
        "noto-fonts-color-emoji",
    ]:
        if required_package not in reported_font_packages:
            fail(f"fontconfig-report.json missing font package: {required_package}")
    expected_fontconfig_tools = {
        "fc-cache",
        "fc-list",
        "fc-match",
        "fc-query",
        "fc-scan",
        "fc-validate",
        "fc-cat",
        "fc-conflist",
        "fc-pattern",
    }
    if set(fontconfig_settings.get("tools") or []) != expected_fontconfig_tools:
        fail("fontconfig-report.json must list all required fc-* tools")
    default_fonts = fontconfig_settings.get("defaultFonts") or {}
    if default_fonts.get("sansSerif") != ["Noto Sans CJK SC", "Noto Sans"]:
        fail("default sans-serif fonts must prefer Noto Sans CJK SC")
    if default_fonts.get("serif") != ["Noto Serif CJK SC", "Noto Serif"]:
        fail("default serif fonts must prefer Noto Serif CJK SC")
    if default_fonts.get("monospace") != ["Noto Sans Mono CJK SC", "Noto Sans Mono"]:
        fail("default monospace fonts must prefer Noto Sans Mono CJK SC")
    if default_fonts.get("emoji") != ["Noto Color Emoji"]:
        fail("default emoji fonts must prefer Noto Color Emoji")
    if fontconfig_settings.get("aliases") != {}:
        fail("default font aliases must be empty")
    if fontconfig_settings.get("includeUserConf") is not True:
        fail("fontconfig must include user XDG config by default")
    if fontconfig_settings.get("globalFontconfigFile") is not None:
        fail("fontconfig must not set a global FONTCONFIG_FILE")
    cache_settings = fontconfig_settings.get("cache") or {}
    if cache_settings.get("preGenerated") is not False:
        fail("fontconfig cache must not be pre-generated")

    if not extensions_report["validation"]["noNetworkDuringProjection"]:
        fail("extensions projection must stay offline")
    if not extensions_report["validation"]["allArtifactsLocked"]:
        fail("extensions-report.json must confirm locked extension artifacts")
    if not extensions_report["validation"]["companionToolsProvidedByNix"]:
        fail("extensions-report.json must confirm companion tools come from Nix")
    if extensions_report["validation"].get("missingCompanionTools"):
        fail("extensions-report.json must not report missing companion tools")
    projection_targets = extensions_index.get("projectionTargets") or []
    if any("$HOME" in target for target in projection_targets):
        fail("VS Code extension projection targets must not retain unexpanded HOME references")
    for required_target in [
        "/home/vscode/.vscode-server/extensions",
        "/home/vscode/.vscode-server-insiders/extensions",
        "/home/vscode/.vscode-remote/extensions",
    ]:
        if required_target not in projection_targets:
            fail(f"extensions-index.json missing projection target: {required_target}")
    seen_extension_ids = set()
    seen_extension_paths = set()
    for extension in extensions_index["extensions"]:
        extension_id = extension["id"]
        extension_path = extension["path"]
        if extension_id in seen_extension_ids:
            fail(f"extensions-index.json must not duplicate extension id: {extension_id}")
        if extension_path in seen_extension_paths:
            fail(f"extensions-index.json must not duplicate extension path: {extension_path}")
        seen_extension_ids.add(extension_id)
        seen_extension_paths.add(extension_path)
        if extension["version"] == "pinned":
            fail(f"extensions-index.json must record a real version for {extension_id}")
        if not extension["source"].startswith("nix-vscode-extensions."):
            fail(f"extensions-index.json must record nix-vscode-extensions source for {extension_id}")
        if not extension["sourceLock"]["ref"]:
            fail(f"extensions-index.json must record source ref for {extension_id}")
    if seen_extension_ids != profile_extension_ids:
        missing_extension_ids = sorted(profile_extension_ids - seen_extension_ids)
        extra_extension_ids = sorted(seen_extension_ids - profile_extension_ids)
        fail(
            "extensions-index.json must match profile-report.json; "
            f"missing={missing_extension_ids}, extra={extra_extension_ids}"
        )
    vscode_settings = ((metadata_preview.get("customizations") or {}).get("vscode") or {}).get("settings") or {}
    if vscode_settings != profile_vscode_settings:
        fail("metadata VS Code settings must match profile-report.json")

    user_report = filesystem_report["user"]
    if user_report["name"] != "vscode" or user_report["uid"] != 1000:
        fail("filesystem-report.json must declare vscode uid 1000")
    if user_report["group"] != "vscode" or user_report["gid"] != 1000:
        fail("filesystem-report.json must declare vscode gid 1000")
    if user_report["home"] != "/home/vscode" or user_report["shell"] != "/bin/bash":
        fail("filesystem-report.json must declare the vscode home and shell")
    nixpkgs_config = filesystem_report.get("nixpkgsConfig") or {}
    if nixpkgs_config.get("path") != "/etc/nixpkgs/config.nix":
        fail("filesystem-report.json must report /etc/nixpkgs/config.nix")
    nixpkgs_config_text = nixpkgs_config.get("text") or ""
    for required_setting in [
        "allowUnfree = true;",
        "android_sdk.accept_license = true;",
        "oraclejdk.accept_license = true;",
        "allowUnsupportedSystem = true;",
    ]:
        if required_setting not in nixpkgs_config_text:
            fail(f"nixpkgs config must include {required_setting}")
    for required_file in ["/etc/profile", "/etc/bashrc", "/etc/bash.bashrc", "/home/vscode/.bashrc"]:
        if required_file not in filesystem_report.get("shellFiles", []):
            fail(f"filesystem-report.json missing generated shell file: {required_file}")
    filesystem_etc_paths = {entry.get("path") for entry in filesystem_report.get("etcFiles", [])}
    for required_etc in [
        "/etc/nix/nix.conf",
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/localtime",
        "/etc/zoneinfo",
        "/etc/gitconfig",
        "/etc/ssh/ssh_config",
        "/etc/ssh/ssh_known_hosts",
    ]:
        if required_etc not in filesystem_etc_paths:
            fail(f"filesystem-report.json missing generated etc file: {required_etc}")
    directory_map = {entry["path"]: entry for entry in filesystem_report["directories"]}
    for required_dir in [
        "/etc/xdg",
        "/home/vscode",
        "/tmp",
        "/var",
        "/var/cache",
        "/var/lib",
        "/var/log",
        "/var/tmp",
        "/run/user/1000",
        "/workspaces",
        "/home/vscode/.codex",
        "/home/vscode/.local/state/bash",
    ]:
        if required_dir not in directory_map:
            fail(f"filesystem-report.json missing directory: {required_dir}")
    if directory_map["/tmp"]["mode"] != "1777" or directory_map["/var/tmp"]["mode"] != "1777":
        fail("filesystem-report.json must declare sticky tmp directories")
    if directory_map["/home/vscode"]["owner"] != "vscode:vscode":
        fail("filesystem-report.json must declare vscode home ownership")
    if directory_map["/run/user/1000"]["mode"] != "0700":
        fail("filesystem-report.json must declare XDG_RUNTIME_DIR as mode 0700")
    if directory_map["/run/user/1000"]["owner"] != "vscode:vscode":
        fail("filesystem-report.json must declare XDG_RUNTIME_DIR ownership as vscode:vscode")
    filesystem_symlinks = {entry.get("path"): entry.get("target") for entry in filesystem_report.get("symlinks", [])}
    if filesystem_symlinks.get("/var/run") != "/run":
        fail("filesystem-report.json must declare /var/run -> /run")
    for nix_dir in [
        "/nix",
        "/nix/store",
        "/nix/var/nix",
        "/nix/var/nix/db",
    ]:
        if nix_dir in directory_map:
            fail(f"filesystem-report.json must leave {nix_dir} to initializeNixDatabase")

    ci_report_files = set(ci_plan["reportFiles"])
    missing_ci_reports = sorted(REQUIRED_CI_REPORT_FILES - ci_report_files)
    if missing_ci_reports:
        fail(f"ci-plan.json missing report files: {', '.join(missing_ci_reports)}")

    if security_report["dockerDaemonBakedIntoImage"]:
        fail("security-report.json must confirm no Docker daemon is baked into the image")
    if security_report["dockerSocketMountedByDefault"]:
        fail("security-report.json must confirm no default Docker socket mount")
    if not security_report["lifecycleLogRedaction"]:
        fail("security-report.json must confirm lifecycle log redaction")
    if not security_report["extensionProjectionLogRedaction"]:
        fail("security-report.json must confirm extension projection log redaction")
    if not security_report["extensionArtifactsLocked"]:
        fail("security-report.json must confirm extension artifacts are locked")
    if security_report["uvxAutoRunFromShellInit"]:
        fail("security-report.json must confirm uvx is not auto-run from shell init")
    if security_report["npxAutoRunFromShellInit"]:
        fail("security-report.json must confirm npx is not auto-run from shell init")
    if not security_report["shellInitHasNoSideEffects"]:
        fail("security-report.json must confirm shell init remains side-effect free")

    if not shell_report.get("enabled"):
        fail("shell-report.json must confirm shell support is enabled")
    if shell_report.get("locale", {}).get("lang") != "en_US.UTF-8":
        fail("shell-report.json must report the default locale")
    if shell_report.get("locale", {}).get("lcAll") is not None:
        fail("shell-report.json must report lcAll as unset by default")
    if not shell_report.get("locale", {}).get("archive", {}).get("enabled"):
        fail("shell-report.json must confirm locale archive support is enabled")
    if "glibc-locales" not in shell_report.get("locale", {}).get("archive", {}).get("path", ""):
        fail("shell-report.json must report the glibc locale archive path")
    for alias_name in ["l", "la", "ll", "ls", "grep", "sha3-256sum"]:
        alias = shell_report.get("aliases", {}).get(alias_name)
        if not alias:
            fail(f"shell-report.json missing default alias: {alias_name}")
        if "core.shell" not in alias.get("origins", []):
            fail(f"default alias {alias_name} must be sourced from core.shell")
    bash_features = shell_report.get("bash", {})
    for feature in ["prompt", "history", "completion", "commandNotFound"]:
        if not bash_features.get(feature):
            fail(f"shell-report.json must enable bash {feature}")
    for required_file in ["/etc/profile", "/etc/bashrc", "/etc/bash.bashrc"]:
        if required_file not in shell_report.get("generatedFiles", []):
            fail(f"shell-report.json missing generated file: {required_file}")
    shell_paths = shell_report.get("imagePaths", [])
    if not any("glibc-locales" in path for path in shell_paths):
        fail("shell-report.json must include glibcLocales in image paths")
    if not any("bash-completion" in path for path in shell_paths):
        fail("shell-report.json must include bash-completion in image paths")

    print(f"report-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
