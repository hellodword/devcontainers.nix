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
  config.devcontainer = {
    layers.bucketDefinitions = {
      "flutter-language" = {
        order = 25000;
        owner = "languages/flutter";
        purpose = "Flutter, Dart, Gradle, and Flutter language tooling.";
      };
      "android-sdk" = {
        order = 25100;
        owner = "languages/flutter";
        purpose = "Android SDK command-line tools used with Flutter.";
      };
      "browser-gui-gpu" = {
        order = 25200;
        owner = "languages/flutter";
        purpose = "Browser and GPU utilities for Flutter web and GUI checks.";
      };
      "vscode-extensions-flutter" = {
        order = 66000;
        owner = "languages/flutter";
        purpose = "Dart and Flutter VS Code extensions.";
      };
    };

    profiles = {
      "language/flutter" = {
        kind = "language";
        group = "flutter-language";
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
              bucket = "vscode-extensions-flutter";
              companionTools = [ "dart" ];
            };
            "dart-code.flutter" = {
              native = false;
              bucket = "vscode-extensions-flutter";
              companionTools = [
                "flutter"
                "dart"
              ];
            };
          };
          settings = {
            "dart.sdkPath" = "${pkgs.dart}";
            "dart.flutterSdkPath" = "${pkgs.flutter}";
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
        tests.cases."language.flutter" = {
          tags = [
            "smoke"
            "language"
            "flutter"
          ];
          command = [
            "bash"
            "-lc"
            "flutter --version && dart --version && java -version && gradle --version && protoc-gen-dart --version"
          ];
          timeoutSeconds = 60;
        };
      };

      "runtime/android-sdk" = {
        kind = "runtime";
        group = "android-sdk";
        packages = android;
        priority = 55;
        stability = "volatile";
        sharing = "single-image";
        securityClass = "trusted";
        provides.commands = [
          "adb"
          "fastboot"
        ];
        tests.cases."runtime.android-sdk" = {
          tags = [
            "smoke"
            "runtime"
            "android"
            "flutter"
          ];
          command = [
            "bash"
            "-lc"
            "command -v adb fastboot >/dev/null"
          ];
        };
      };

      "runtime/browser-gui-gpu" = {
        kind = "runtime";
        group = "browser-gui-gpu";
        packages = browserGpu;
        priority = 50;
        stability = "volatile";
        sharing = "single-image";
        securityClass = "trusted";
        provides.commands = [
          "chromium"
          "glxinfo"
        ];
        tests.cases."runtime.browser-gui-gpu" = {
          tags = [
            "smoke"
            "runtime"
            "browser"
            "gui"
            "gpu"
            "flutter"
          ];
          command = [
            "bash"
            "-lc"
            "command -v chromium glxinfo >/dev/null"
          ];
        };
      };

      "language/flutter-rust-bridge" = {
        kind = "language";
        group = "flutter-language";
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
        tests.cases."language.flutter-rust-bridge" = {
          tags = [
            "smoke"
            "language"
            "flutter"
            "rust-bridge"
          ];
          command = [
            "bash"
            "-lc"
            "flutter_rust_bridge_codegen --version && sqlx --version && sqlite3 --version && command -v sqlitebrowser >/dev/null"
          ];
        };
      };
    };
  };
}
