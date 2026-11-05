#!/usr/bin/env bash
# Xcode Cloud: writes the git-ignored Config/Secrets.xcconfig from the
# workflow's secret environment variables, which Config/OpenCast.xcconfig
# includes. A missing variable leaves that setting blank (no built-in Gemini
# key, or notifications kept on device), as in a checkout without secrets.
set -euo pipefail

secrets="${CI_PRIMARY_REPOSITORY_PATH}/Config/Secrets.xcconfig"

{
  echo "// Written by ci_scripts/ci_post_clone.sh."
  if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    echo "GEMINI_API_KEY = ${GEMINI_API_KEY}"
  else
    echo "warning: GEMINI_API_KEY is not set; the build has no built-in Gemini key" >&2
  fi
  if [[ -n "${NOTIFICATIONS_WORKER:-}" ]]; then
    # xcconfig treats "//" as a comment, so the host goes in without a scheme.
    echo "NOTIFICATIONS_WORKER = ${NOTIFICATIONS_WORKER#https://}"
  else
    echo "warning: NOTIFICATIONS_WORKER is not set; notifications stay on device" >&2
  fi
} > "${secrets}"

echo "Wrote ${secrets}"
