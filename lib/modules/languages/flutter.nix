{
  lib,
  pkgs,
  config,
  ...
}:
let
  flutterCore = with pkgs; [
    flutter
    dart
    jdk17
    gradle
    protoc-gen-dart
  ];
  android = with pkgs; [ android-tools ];
  browserGpu = with pkgs; [
    chromium
    mesa-demos
  ];
  flutterRustBridge = with pkgs; [
    flutter_rust_bridge_codegen
    sqlite
    sqlx-cli
    sqlitebrowser
  ];
in
{
  config = lib.mkIf config.devcontainer.languages.flutter.enable {
    environment.systemPackages = flutterCore ++ android ++ browserGpu ++ flutterRustBridge;
    devcontainer.vscode.extensions = [
      "dart-code.dart-code"
      "dart-code.flutter"
      "rust-lang.rust-analyzer"
    ];
    devcontainer.vscode.settings = {
      "dart.checkForSdkUpdates" = false;
      "dart.updateDevTools" = false;
      "dart.debugSdkLibraries" = true;
      "dart.debugExternalPackageLibraries" = true;
      "json.schemas" = [
        {
          fileMatch = [ "*.arb" ];
          url = "https://raw.githubusercontent.com/google/app-resource-bundle/main/schema.json";
        }
      ];
    };
    environment.variables = {
      JAVA_HOME = "${pkgs.jdk17.home}";
      FLUTTER_ROOT = "${pkgs.flutter}";
      FLUTTER_SUPPRESS_ANALYTICS = "true";
      COMPILER_INDEX_STORE_ENABLE = "NO";
      PUB_CACHE = "$XDG_CACHE_HOME/pub";
      GRADLE_USER_HOME = "$XDG_CACHE_HOME/gradle";
      ANDROID_SDK_ROOT = "$XDG_DATA_HOME/android-sdk-overlay";
      ANDROID_USER_HOME = "$XDG_DATA_HOME/android";
    };
    environment.variableOrigins = {
      JAVA_HOME = [ "languages.flutter" ];
      FLUTTER_ROOT = [ "languages.flutter" ];
      FLUTTER_SUPPRESS_ANALYTICS = [ "languages.flutter" ];
      COMPILER_INDEX_STORE_ENABLE = [ "languages.flutter" ];
      PUB_CACHE = [ "languages.flutter" ];
      GRADLE_USER_HOME = [ "languages.flutter" ];
      ANDROID_SDK_ROOT = [ "languages.flutter" ];
      ANDROID_USER_HOME = [ "languages.flutter" ];
    };
    environment.interactiveShellInit = ''
      if command -v flutter >/dev/null 2>&1; then
        . <(flutter bash-completion) 2>/dev/null || true
      fi
    '';
    devcontainer.path.segments.language = [ "$PUB_CACHE/bin" ];
    devcontainer.path.segmentOrigins.language = {
      "$PUB_CACHE/bin" = [ "languages.flutter" ];
    };
    devcontainer.graph.nodes."language/flutter" = {
      kind = "language";
      group = "60-flutter-language";
      paths = flutterCore;
      stability = "volatile";
      sharing = "single-image";
      priority = 60;
      securityClass = "trusted";
    };
    devcontainer.graph.nodes."runtime/android-sdk" = {
      kind = "runtime";
      group = "61-android-sdk";
      paths = android;
      stability = "volatile";
      sharing = "single-image";
      priority = 55;
      securityClass = "trusted";
    };
    devcontainer.graph.nodes."runtime/browser-gui-gpu" = {
      kind = "runtime";
      group = "62-browser-gui-gpu";
      paths = browserGpu;
      stability = "volatile";
      sharing = "single-image";
      priority = 50;
      securityClass = "trusted";
    };
    devcontainer.graph.nodes."language/flutter-rust-bridge" = {
      kind = "language";
      group = "60-flutter-language";
      paths = flutterRustBridge;
      stability = "volatile";
      sharing = "single-image";
      priority = 58;
      securityClass = "trusted";
    };
    devcontainer.lifecycle.tasks = {
      "dart-disable-analytics" = {
        phase = "postCreate";
        once = true;
        user = "vscode";
        command = [
          "bash"
          "-lc"
          "command -v dart >/dev/null 2>&1 && dart --disable-analytics || true"
        ];
        timeoutSeconds = 30;
        needs = [ "xdg-dirs" ];
      };
      "flutter-disable-analytics" = {
        phase = "postCreate";
        once = true;
        user = "vscode";
        command = [
          "bash"
          "-lc"
          "command -v flutter >/dev/null 2>&1 && flutter --disable-analytics || true"
        ];
        timeoutSeconds = 30;
        needs = [ "xdg-dirs" ];
      };
    };
    devcontainer.tests.smoke = [
      {
        name = "flutter-version";
        command = [
          "flutter"
          "--version"
        ];
      }
      {
        name = "dart-version";
        command = [
          "dart"
          "--version"
        ];
      }
      {
        name = "flutter-tooling";
        command = [
          "bash"
          "-lc"
          "java -version && gradle --version && rustc --version && node --version && python --version && protoc-gen-dart --version && flutter_rust_bridge_codegen --version && sqlx --version && sqlite3 --version"
        ];
      }
    ];
  };
}
