{ self }:
{
  image = self.images."go-latest";
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "runtime/c-env"
    "language/go"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
