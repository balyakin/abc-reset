#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$project_dir"

mkdir -p .build
xcrun swiftc -Onone -parse-as-library \
    Sources/ABCReset/ResetPolicy.swift \
    Sources/ABCReset/KeyboardState.swift \
    Sources/ABCReset/InputSources.swift \
    Tests/*.swift \
    -o .build/ABCResetChecks

.build/ABCResetChecks
