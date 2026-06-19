{ self }:
{
  image = self.images."rust-web";
  expectedNodes = [
    "language/rust"
    "language/nodejs"
    "toolset/data-network"
  ];
}
