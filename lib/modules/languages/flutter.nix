{
  pkgs,
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
  config.devcontainer.profiles = {
    "language/flutter" = {
      kind = "language";
      group = "60-flutter-language";
      packages = flutterCore;
      priority = 60;
      stability = "volatile";
      sharing = "single-image";
      securityClass = "trusted";
      provides.commands = [
        "flutter"
        "dart"
        "java"
        "gradle"
        "protoc-gen-dart"
      ];
      vscode = {
        extensions = {
          "dart-code.dart-code" = {
            native = false;
            bucket = "86-vscode-extensions-flutter";
            companionTools = [ "dart" ];
          };
          "dart-code.flutter" = {
            native = false;
            bucket = "86-vscode-extensions-flutter";
            companionTools = [
              "flutter"
              "dart"
            ];
          };
        };
        settings = {
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
      };
      env = {
        variables = {
          JAVA_HOME = "${pkgs.jdk17.home}";
          FLUTTER_ROOT = "${pkgs.flutter}";
          FLUTTER_SUPPRESS_ANALYTICS = "true";
          COMPILER_INDEX_STORE_ENABLE = "NO";
          PUB_CACHE = "$XDG_CACHE_HOME/pub";
          GRADLE_USER_HOME = "$XDG_CACHE_HOME/gradle";
          ANDROID_SDK_ROOT = "$XDG_DATA_HOME/android-sdk-overlay";
          ANDROID_USER_HOME = "$XDG_DATA_HOME/android";
        };
        path = [ "$PUB_CACHE/bin" ];
        interactiveShellInit = ''
          if command -v flutter >/dev/null 2>&1; then
            . <(flutter bash-completion) 2>/dev/null || true
          fi
        '';
      };
      lifecycle.tasks = {
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
      tests.capabilities = [ "language.flutter" ];
    };

    "runtime/android-sdk" = {
      kind = "runtime";
      group = "61-android-sdk";
      packages = android;
      priority = 55;
      stability = "volatile";
      sharing = "single-image";
      securityClass = "trusted";
      provides.commands = [
        "adb"
        "fastboot"
      ];
      tests.capabilities = [ "runtime.android-sdk" ];
    };

    "runtime/browser-gui-gpu" = {
      kind = "runtime";
      group = "62-browser-gui-gpu";
      packages = browserGpu;
      priority = 50;
      stability = "volatile";
      sharing = "single-image";
      securityClass = "trusted";
      provides.commands = [
        "chromium"
        "glxinfo"
      ];
      tests.capabilities = [ "runtime.browser-gui-gpu" ];
    };

    "language/flutter-rust-bridge" = {
      kind = "language";
      group = "60-flutter-language";
      packages = flutterRustBridge;
      priority = 58;
      stability = "volatile";
      sharing = "single-image";
      securityClass = "trusted";
      provides.commands = [
        "flutter_rust_bridge_codegen"
        "sqlite3"
        "sqlx"
        "sqlitebrowser"
      ];
      tests.capabilities = [ "language.flutter-rust-bridge" ];
    };
  };
}
