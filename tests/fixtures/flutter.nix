{ self }:
{
  image = self.images."flutter-latest";
  expectedNodes = [
    "language/rust"
    "language/nodejs"
    "language/flutter"
    "language/flutter-rust-bridge"
    "toolset/editor-support"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
