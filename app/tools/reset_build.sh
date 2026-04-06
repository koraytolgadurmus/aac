#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
app_dir=$(CDPATH= cd "$script_dir/.." && pwd)

if [[ "${PWD}" != "${app_dir}" ]]; then
  echo "Please run from the app directory: ${app_dir}" >&2
  exit 1
fi

if [[ ! -f "${app_dir}/pubspec.yaml" ]]; then
  echo "pubspec.yaml not found in ${app_dir}. Aborting." >&2
  exit 1
fi

rm -rf \
  "${app_dir}/.dart_tool" \
  "${app_dir}/build" \
  "${app_dir}/android/.gradle" \
  "${app_dir}/android/app/build" \
  "${app_dir}/android/app/.cxx"

if [[ -d "${app_dir}/ios/Pods" ]]; then
  rm -rf "${app_dir}/ios/Pods"
fi

if [[ -d "${app_dir}/ios/.symlinks" ]]; then
  rm -rf "${app_dir}/ios/.symlinks"
fi

flutter clean
flutter pub get
(
  cd "${app_dir}/android"
  ./gradlew clean
)
