#!/bin/bash
# Fails if any xcodebuild log passed as an argument reports a warning or error in this
# project's own files. Toolchain notices that point elsewhere are printed but not fatal.
# Usage: Tools/check_xcodebuild_warnings.sh build.log [test.log ...]
set -u
cd "$(dirname "$0")/.."
PROJECT_DIR=$(pwd)

cat "$@" 2>/dev/null | grep -E "(warning|error):" | sort -u > issues.txt || true
echo "All issues reported by xcodebuild:"
cat issues.txt

grep -E "$PROJECT_DIR/(SnoreGuard|SnoreGuardTests|Config)/" issues.txt > project-issues.txt || true
if [ -s project-issues.txt ]; then
    echo "::error::Warnings or errors in project sources"
    cat project-issues.txt
    exit 1
fi
echo "No warnings or errors in project sources."
