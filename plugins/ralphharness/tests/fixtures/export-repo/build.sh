#!/usr/bin/env bash
set -e
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/.roo/commands"
echo "Export-repo fixture built at $TMP_DIR"
