#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/check-gui-env.sh"
"$script_dir/check-vscode-extension-projector.sh"
"$script_dir/check-task-runner.sh"
"$script_dir/check-devpkg.sh"

echo "runtime-tools-check ok"
