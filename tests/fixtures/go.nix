{ self }:
{
  image = self.images."go-latest";
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "runtime/c-env"
    "language/go"
    "toolset/editor-support"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
