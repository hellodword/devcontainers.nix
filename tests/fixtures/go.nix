{ self }:
{
  image = self.images.go;
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "runtime/c-env"
    "language/go"
  ];
}
