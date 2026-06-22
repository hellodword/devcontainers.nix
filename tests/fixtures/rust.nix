{ self }:
{
  image = self.images."rust";
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "runtime/c-env"
    "language/rust"
    "toolset/editor-support"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
