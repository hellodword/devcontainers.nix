{ self }:
{
  image = self.images."rust-web";
  expectedNodes = [
    "language/rust"
    "language/nodejs"
    "toolset/editor-support"
    "toolset/data-network"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
