#!/bin/sh
# Sets the macOS app version in project.yml. Releases are tagged vX.Y.Z; the Windows/Linux app uses the same number.
#   scripts/set-version.sh 0.1.1
set -eu
cd "$(dirname "$0")/.."
NEW=${1:?usage: scripts/set-version.sh X.Y.Z}
echo "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Version must look like 1.2.3" >&2; exit 1; }
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: $NEW/" project.yml
BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: $((BUILD + 1))/" project.yml
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml
