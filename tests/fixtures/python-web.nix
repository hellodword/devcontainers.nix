{ self }:
{
  image = self.images."python-web";
  expectedNodes = [
    "language/python"
    "language/nodejs"
    "toolset/data-network"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
