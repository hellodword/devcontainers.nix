{ self }:
{
  image = self.images."go-web";
  expectedNodes = [
    "language/go"
    "language/nodejs"
    "toolset/editor-support"
    "toolset/data-network"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
