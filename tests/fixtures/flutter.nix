{ self }:
{
  image = self.images.flutter;
  expectedNodes = [
    "language/rust"
    "language/nodejs"
    "language/flutter"
  ];
}
