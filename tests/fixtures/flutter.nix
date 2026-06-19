{ self }:
{
  image = self.images.flutter;
  expectedNodes = [
    "language/rust"
    "language/nodejs"
    "language/flutter"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
