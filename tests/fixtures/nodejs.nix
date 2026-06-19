{ self }:
{
  image = self.images.nodejs;
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "language/nodejs"
  ];
}
