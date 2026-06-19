{ self }:
{
  image = self.images.python;
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "language/python"
  ];
}
