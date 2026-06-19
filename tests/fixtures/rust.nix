{ self }:
{
  image = self.images.rust;
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "runtime/c-env"
    "language/rust"
  ];
}
