{ lib, pkgs, config, ... }:
let
  flutterCore = with pkgs; [ flutter dart jdk17 gradle ];
  android = with pkgs; [ android-tools ];
  browserGpu = with pkgs; [ chromium mesa-demos ];
in
{
  config = lib.mkIf config.devcontainer.languages.flutter.enable {
    devcontainer.packages = flutterCore ++ android ++ browserGpu;
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
    };
    devcontainer.env.container = {
      FLUTTER_SUPPRESS_ANALYTICS = "true";
      PUB_CACHE = "$XDG_CACHE_HOME/pub";
      GRADLE_USER_HOME = "$XDG_CACHE_HOME/gradle";
      ANDROID_SDK_ROOT = "$XDG_DATA_HOME/android-sdk-overlay";
      ANDROID_USER_HOME = "$XDG_DATA_HOME/android";
    };
    devcontainer.env.origins.container = {
      FLUTTER_SUPPRESS_ANALYTICS = [ "languages.flutter" ];
      PUB_CACHE = [ "languages.flutter" ];
      GRADLE_USER_HOME = [ "languages.flutter" ];
      ANDROID_SDK_ROOT = [ "languages.flutter" ];
      ANDROID_USER_HOME = [ "languages.flutter" ];
    };
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
    devcontainer.tests.smoke = [
      {
        name = "flutter-version";
        command = [ "flutter" "--version" ];
      }
      {
        name = "dart-version";
        command = [ "dart" "--version" ];
      }
      {
        name = "flutter-tooling";
        command = [ "bash" "-lc" "java -version && gradle --version && rustc --version && node --version && python --version" ];
      }
    ];
  };
}
