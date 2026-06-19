{ self }:
{
  image = self.images."nodejs-latest";
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "language/nodejs"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
