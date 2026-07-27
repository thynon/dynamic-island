#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/dynamic-island-approval-checks.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

core_sources=("$repo_root"/Sources/DynamicIslandCore/*.swift)

swiftc \
    -swift-version 6 \
    -parse-as-library \
    -emit-module \
    -emit-library \
    -static \
    -module-name DynamicIslandCore \
    -emit-module-path "$build_dir/DynamicIslandCore.swiftmodule" \
    -o "$build_dir/libDynamicIslandCore.a" \
    "${core_sources[@]}"

swiftc \
    -swift-version 6 \
    -parse-as-library \
    -I "$build_dir" \
    -L "$build_dir" \
    -lDynamicIslandCore \
    "$repo_root/Sources/DynamicIsland/Support/CodexAppServerApprovalClient.swift" \
    "$repo_root/Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift" \
    "$repo_root/Tests/DynamicIslandApprovalChecks/main.swift" \
    -o "$build_dir/DynamicIslandApprovalChecks"

"$build_dir/DynamicIslandApprovalChecks"
