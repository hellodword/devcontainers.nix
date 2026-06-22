{ self }:
{
  image = self.images."nodejs";
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "language/nodejs"
    "toolset/editor-support"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
