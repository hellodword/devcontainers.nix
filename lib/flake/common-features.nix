{
  lib,
  withNix,
  features,
}:
(with features; [
  (dev0 { })
  (dev1 { })
  (dev2 { })

  (prettier { })
  (markdown { })
  (xml { })
  (toml { })
  (jinja { })
  (protobuf { })

  # (autocorrect { })
  # (grammarly { })

  (shellcheck { })

  # (drawio { })
  # (graphviz { })

  (copilot { })
])
++ (lib.optionals withNix [
  (features.nix-core { })
])
