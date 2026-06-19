{ self }:
{
  image = self.images."go-web";
  expectedNodes = [
    "language/go"
    "language/nodejs"
    "toolset/data-network"
  ];
}
