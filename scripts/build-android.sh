#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-$project_root/.tooling/flutter/bin/flutter}"
mode="${1:-debug}"
api_url="${2:-http://10.0.2.2:3001}"
if [[ "$mode" != debug && "$mode" != release ]]; then
  echo 'Usage: scripts/build-android.sh debug|release API_URL' >&2
  exit 1
fi
if [[ "$mode" == release && "$api_url" != https://* ]]; then
  echo 'Release requires your deployed HTTPS backend URL.' >&2
  exit 1
fi
if [[ "$mode" == release && ! -f "$project_root/mobile/android/key.properties" ]]; then
  echo 'Add your upload signing key in mobile/android/key.properties first.' >&2
  exit 1
fi
cd "$project_root/mobile"
export PUB_CACHE="${PUB_CACHE:-$project_root/.tooling/pub-cache}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$project_root/.tooling/gradle}"
if [[ -d "$project_root/.tooling/android-sdk" ]]; then
  export ANDROID_HOME="$project_root/.tooling/android-sdk"
fi
"$flutter_bin" pub get
"$flutter_bin" analyze
"$flutter_bin" test
"$flutter_bin" build apk "--$mode" "--dart-define=API_BASE_URL=$api_url"
mkdir -p "$project_root/artifacts"
cp "build/app/outputs/flutter-apk/app-$mode.apk" "$project_root/artifacts/krishi-saathi-$mode.apk"
if [[ "$mode" == release ]]; then
  "$flutter_bin" build appbundle --release "--dart-define=API_BASE_URL=$api_url"
  cp build/app/outputs/bundle/release/app-release.aab "$project_root/artifacts/krishi-saathi-release.aab"
fi
