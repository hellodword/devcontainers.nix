{ self }:
{
  image = self.images."rust-latest";
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "runtime/c-env"
    "language/rust"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
