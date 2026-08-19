#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONTROL_SCRIPT="$SCRIPT_DIR/release-control.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cherry-image-release-control.XXXXXX")"
export GIT_ALLOW_PROTOCOL=file:git:ssh:https:http

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT
fail() { printf 'release-control test failed: %s\n' "$1" >&2; exit 1; }

expect_failure() {
    local expected="$1" output status
    shift
    set +e
    output="$($@ 2>&1)"
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "command unexpectedly succeeded: $*"
    printf '%s\n' "$output" | grep -Fq -- "$expected" || fail "failure did not include '$expected': $output"
}

CANVAS_ORIGIN="$TEST_ROOT/canvas-origin.git"
CANVAS_SOURCE="$TEST_ROOT/canvas-source"
REPO_ORIGIN="$TEST_ROOT/image-origin.git"
REPO="$TEST_ROOT/image"
STATE="$TEST_ROOT/state/tasks"
WORKTREES="$TEST_ROOT/worktrees"
mkdir -p "$CANVAS_SOURCE" "$REPO"

git init --bare -q "$CANVAS_ORIGIN"
git -C "$CANVAS_SOURCE" init -q
git -C "$CANVAS_SOURCE" config user.name test
git -C "$CANVAS_SOURCE" config user.email test@example.invalid
mkdir -p "$CANVAS_SOURCE/web/src/constant" "$CANVAS_SOURCE/web/src/stores"
printf '%s\n' 'export const FIXED_API_BASE_URL = (import.meta.env.VITE_FIXED_API_BASE_URL || "").trim().replace(/\/+$/, "");' > "$CANVAS_SOURCE/web/src/constant/env.ts"
printf '%s\n' 'import { FIXED_API_BASE_URL } from "@/constant/env";' 'const OPENAI_BASE_URL = FIXED_API_BASE_URL;' > "$CANVAS_SOURCE/web/src/stores/use-config-store.ts"
printf '%s\n' 'export default { base: appBase, };' > "$CANVAS_SOURCE/web/vite.config.ts"
printf '%s\n' 'const router = { basename: import.meta.env.BASE_URL };' > "$CANVAS_SOURCE/web/src/router.tsx"
printf '%s\n' 'FROM oven/bun:latest' 'ARG VITE_BASE=/canvas/' 'ENV VITE_BASE=${VITE_BASE}' 'ARG VITE_FIXED_API_BASE_URL=' 'ENV VITE_FIXED_API_BASE_URL=${VITE_FIXED_API_BASE_URL}' > "$CANVAS_SOURCE/Dockerfile"
git -C "$CANVAS_SOURCE" add .
git -C "$CANVAS_SOURCE" commit -qm canvas-initial
git -C "$CANVAS_SOURCE" branch -M main
git -C "$CANVAS_SOURCE" remote add origin "$CANVAS_ORIGIN"
git -C "$CANVAS_SOURCE" push -qu origin main
git --git-dir="$CANVAS_ORIGIN" symbolic-ref HEAD refs/heads/main
CANVAS_COMMIT="$(git -C "$CANVAS_SOURCE" rev-parse HEAD)"

git init --bare -q "$REPO_ORIGIN"
git -C "$REPO" init -q
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config protocol.file.allow always
printf '%s\n' 'FROM oven/bun:latest' 'ARG VITE_BASE=/' 'ENV VITE_BASE=${VITE_BASE}' 'ARG VITE_FIXED_API_BASE_URL' 'ENV VITE_FIXED_API_BASE_URL=${VITE_FIXED_API_BASE_URL}' > "$REPO/Dockerfile"
printf '%s\n' 'shell source' > "$REPO/README.md"
git -C "$REPO" add Dockerfile README.md
git -C "$REPO" commit -qm shell-initial
git -C "$REPO" -c protocol.file.allow=always submodule add -q "$CANVAS_ORIGIN" vendor/infinite-canvas
git -C "$REPO" add .gitmodules vendor/infinite-canvas
git -C "$REPO" commit -qm add-canvas-gitlink
git -C "$REPO" branch -M main
git -C "$REPO" remote add origin "$REPO_ORIGIN"
git -C "$REPO" push -qu origin main
PARENT_COMMIT="$(git -C "$REPO" rev-parse HEAD)"

PROFILE_OUTPUT="$(bash "$CONTROL_SCRIPT" profile --repo-root "$REPO" --domain aiunify.xyz)"
printf '%s\n' "$PROFILE_OUTPUT" | grep -Fx 'origin=https://aiunify.xyz' >/dev/null || fail "profile origin"
printf '%s\n' "$PROFILE_OUTPUT" | grep -Fx 'remote_actions=none' >/dev/null || fail "profile remote boundary"

bash "$CONTROL_SCRIPT" prepare-matrix --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --task-prefix matrix --source-ref "$PARENT_COMMIT" >/dev/null

for domain in gptch.cloud artworkers.online aiunify.xyz; do
    task_id="matrix-${domain//./-}"
    release_ref="refs/image-release/$domain/$task_id/$PARENT_COMMIT"
    test "$(git -C "$REPO" rev-parse --verify "$release_ref")" = "$PARENT_COMMIT" || fail "release ref for $domain"
    manifest="$STATE/$task_id/process.md"
    grep -Fq -- "- Domain: $domain" "$manifest" || fail "manifest domain for $domain"
    grep -Fq -- "- Source Line: main" "$manifest" || fail "manifest source line for $domain"
    grep -Fq -- "- Release Ref: $release_ref" "$manifest" || fail "manifest release ref for $domain"
    grep -Fq -- "VITE_FIXED_API_BASE_URL=https://$domain" "$manifest" || fail "build origin for $domain"
    worktree="$WORKTREES/$task_id"
    test -z "$(git -C "$worktree" symbolic-ref -q HEAD || true)" || fail "worktree is attached for $domain"
    test "$(git -C "$worktree/vendor/infinite-canvas" rev-parse HEAD)" = "$CANVAS_COMMIT" || fail "Canvas pair for $domain"
    test -z "$(git -C "$worktree" status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" || fail "worktree is dirty for $domain"
done

expect_failure 'duplicate matrix domain: gptch.cloud' bash "$CONTROL_SCRIPT" prepare-matrix --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --task-prefix duplicate --source-ref "$PARENT_COMMIT" --domains gptch.cloud,gptch.cloud

printf 'image release-control tests passed\n'
