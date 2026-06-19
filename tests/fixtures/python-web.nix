{ self }:
{
  image = self.images."python-web";
  expectedNodes = [
    "language/python"
    "language/nodejs"
    "toolset/data-network"
  ];
}
