#!/bin/bash
#
# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Some simple smoke tests for "bazel dump".


# --- begin runfiles.bash initialization ---
set -euo pipefail
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---

source "$(rlocation "io_bazel/src/test/shell/integration_test_setup.sh")" \
  || { echo "integration_test_setup.sh not found!" >&2; exit 1; }

case "$(uname -s | tr [:upper:] [:lower:])" in
msys*|mingw*|cygwin*)
  declare -r is_windows=true
  ;;
*)
  declare -r is_windows=false
  ;;
esac

if "$is_windows"; then
  export MSYS_NO_PATHCONV=1
  export MSYS2_ARG_CONV_EXCL="*"
fi

function set_up() {
  # So that each test starts with a clean slate. Important so that the output of
  # dumping various things is predictable.
  bazel shutdown
}

function test_memory_summary() {
  mkdir -p a
  cat > a/BUILD <<'EOF'
sh_library(name='a')
EOF

  bazel query //a:all >& $TEST_log || fail "query failed"
  bazel dump --memory=deep,summary:package://a >& $TEST_log \
    || fail "dump failed"
  expect_log "objects,.*bytes retained"
}

function test_memory_shallow() {
  mkdir -p a
  cat > a/BUILD <<'EOF'
load(":a.bzl", "a")
EOF

  cat > a/a.bzl <<'EOF'
load(":b.bzl", "b")
a = {}
EOF

  cat > a/b.bzl <<'EOF'
b = {}
EOF

  bazel query //a:all >& $TEST_log || fail "query failed"
  bazel dump --memory=shallow,count:starlark_module://a:a.bzl >& $TEST_log \
    || fail "dump failed"
  expect_log "^net.starlark.java.eval.Module: 1"  # Only a.bzl, not b.bzl
}

function test_memory_needle() {
  mkdir -p a
  cat > a/BUILD <<'EOF'
EOF

  bazel query //a:all >& $TEST_log || fail "query failed"
  bazel dump --memory=shallow,count,needle=com.google.devtools.build.lib.packages.Package:package://a >& $TEST_log || fail "dump failed"
  expect_log "Needle reached by path:"
  bazel dump --memory=shallow,count,needle=com.google.devtools.build.lib.packages.Rule:package://a >& $TEST_log || fail "dump failed"
  expect_not_log "Needle reached by path:"
}

run_suite "Tests for 'bazel dump'"
