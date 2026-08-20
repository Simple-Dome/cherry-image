#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONTROL_SCRIPT="$SCRIPT_DIR/release-control.sh"
CANVAS_CONTRACT_SCRIPT="$SCRIPT_DIR/validate-canvas-contract.py"
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

# The contract validator must accept equivalent fixed-base implementations,
# including a provider fallback after the fixed value, without accepting a
# fallback that takes precedence over the selected-domain value.
CANVAS_FALLBACK="$TEST_ROOT/canvas-fallback"
mkdir -p "$CANVAS_FALLBACK/web/src/constant" "$CANVAS_FALLBACK/web/src/stores"
cp "$CANVAS_SOURCE/web/src/constant/env.ts" "$CANVAS_FALLBACK/web/src/constant/env.ts"
printf '%s\n' 'import { FIXED_API_BASE_URL } from "@/constant/env";' 'const OPENAI_BASE_URL = FIXED_API_BASE_URL || "https://api.openai.com";' > "$CANVAS_FALLBACK/web/src/stores/use-config-store.ts"
python3 "$CANVAS_CONTRACT_SCRIPT" "$CANVAS_FALLBACK" gptch.cloud | grep -Fx 'canvas_contract=semantic-pass' >/dev/null || fail "fallback contract"
printf '%s\n' 'import { FIXED_API_BASE_URL } from "@/constant/env";' 'const OPENAI_BASE_URL = "https://api.openai.com" || FIXED_API_BASE_URL;' > "$CANVAS_FALLBACK/web/src/stores/use-config-store.ts"
expect_failure 'OPENAI_BASE_URL must prefer FIXED_API_BASE_URL' python3 "$CANVAS_CONTRACT_SCRIPT" "$CANVAS_FALLBACK" gptch.cloud
printf '%s\n' 'import { FIXED_API_BASE_URL } from "@/constant/env";' 'const OPENAI_BASE_URL = FIXED_API_BASE_URL || "https://api.openai.com";' 'const forbidden = "https://artworkers.online";' > "$CANVAS_FALLBACK/web/src/stores/use-config-store.ts"
expect_failure 'source contains forbidden domain artworkers.online' python3 "$CANVAS_CONTRACT_SCRIPT" "$CANVAS_FALLBACK" gptch.cloud

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

# The attached checkout is a controller only. Its local files must neither
# block preparation nor appear in the detached release source worktree.
printf 'controller-only\n' > "$REPO/controller-only.txt"

PROFILE_OUTPUT="$(bash "$CONTROL_SCRIPT" profile --repo-root "$REPO" --domain aiunify.xyz)"
printf '%s\n' "$PROFILE_OUTPUT" | grep -Fx 'origin=https://aiunify.xyz' >/dev/null || fail "profile origin"
printf '%s\n' "$PROFILE_OUTPUT" | grep -Fx 'documented_status=unverified' >/dev/null || fail "documented profile status"
printf '%s\n' "$PROFILE_OUTPUT" | grep -Fx 'live_status=not-recorded' >/dev/null || fail "profile has no live topology"
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
    test ! -e "$worktree/controller-only.txt" || fail "controller file leaked into $domain release worktree"
done

HANDOFF_TASK='handoff-process'
HANDOFF_MANIFEST="$STATE/$HANDOFF_TASK/process.md"
mkdir -p "$STATE/$HANDOFF_TASK"
printf '%s\n' '## Current Task' '- Fresh release handoff before controller initialization.' >"$HANDOFF_MANIFEST"
bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$HANDOFF_TASK" --domain gptch.cloud --source-ref "$PARENT_COMMIT" >/dev/null
grep -Fx -- '- Current Phase: source-prepared' "$HANDOFF_MANIFEST" >/dev/null || fail 'handoff process initializes release state'

STATE_TASK="state-machine"
STATE_MANIFEST="$STATE/$STATE_TASK/process.md"
bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$STATE_TASK" --domain gptch.cloud --source-ref "$PARENT_COMMIT" >/dev/null
grep -Fx -- '- Current Phase: source-prepared' "$STATE_MANIFEST" >/dev/null || fail 'source-prepared release state'
# An active task may resume with the exact same detached worktree and source pair.
bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$STATE_TASK" --domain gptch.cloud --source-ref "$PARENT_COMMIT" >/dev/null
git -C "$WORKTREES/$STATE_TASK" checkout -qb unsafe-attached
expect_failure 'prepared worktree must be detached' bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$STATE_TASK" --domain gptch.cloud --source-ref "$PARENT_COMMIT"
git -C "$WORKTREES/$STATE_TASK" checkout -q --detach "$PARENT_COMMIT"
bash "$CONTROL_SCRIPT" prepare-composite --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$STATE_TASK" --domain gptch.cloud >/dev/null
grep -Fx -- '- Current Phase: composite-prepared' "$STATE_MANIFEST" >/dev/null || fail 'composite-prepared release state'
DRY_RUN_OUTPUT="$(bash "$CONTROL_SCRIPT" dry-run --repo-root "$REPO" --state-root "$STATE" --task-id "$STATE_TASK" --phase local-preparation)"
printf '%s\n' "$DRY_RUN_OUTPUT" | grep -Fx 'current_phase=local-preparation-verified' >/dev/null || fail 'dry-run state output'
grep -Fx -- '- Current Phase: local-preparation-verified' "$STATE_MANIFEST" >/dev/null || fail 'local-preparation-verified release state'
expect_failure 'prepare-composite is not allowed at release phase local-preparation-verified' bash "$CONTROL_SCRIPT" prepare-composite --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$STATE_TASK" --domain gptch.cloud

LIVE_EVIDENCE="$TEST_ROOT/live-topology.env"
LIVE_OBSERVED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '%s\n' \
    'domain=gptch.cloud' \
    "observed_at=$LIVE_OBSERVED_AT" \
    'shell_bluegreen=ready' \
    'canvas_bluegreen=ready' \
    'uploads_bluegreen=ready' \
    'minio_isolation=ready' >"$LIVE_EVIDENCE"
LIVE_RECORD_OUTPUT="$(bash "$CONTROL_SCRIPT" record-live-topology --repo-root "$REPO" --state-root "$STATE" --task-id "$STATE_TASK" --domain gptch.cloud --evidence-file "$LIVE_EVIDENCE")"
printf '%s\n' "$LIVE_RECORD_OUTPUT" | grep -Fx 'documented_status=unverified' >/dev/null || fail 'documented status remains separate'
printf '%s\n' "$LIVE_RECORD_OUTPUT" | grep -Fx 'live_status=ready-for-bluegreen' >/dev/null || fail 'ready live topology status'
grep -Fx -- '- Current Phase: live-discovery-recorded' "$STATE_MANIFEST" >/dev/null || fail 'live topology advances release phase'
LIVE_STATUS_OUTPUT="$(bash "$CONTROL_SCRIPT" live-status --repo-root "$REPO" --state-root "$STATE" --task-id "$STATE_TASK" --domain gptch.cloud)"
printf '%s\n' "$LIVE_STATUS_OUTPUT" | grep -Fx 'live_status=ready-for-bluegreen' >/dev/null || fail 'live status report'
bash "$CONTROL_SCRIPT" assert-live-ready --repo-root "$REPO" --state-root "$STATE" --task-id "$STATE_TASK" --domain gptch.cloud --max-age-seconds 60 >/dev/null

printf '%s\n' \
    'domain=gptch.cloud' \
    'observed_at=2000-01-01T00:00:00Z' \
    'shell_bluegreen=ready' \
    'canvas_bluegreen=ready' \
    'uploads_bluegreen=ready' \
    'minio_isolation=ready' >"$LIVE_EVIDENCE"
bash "$CONTROL_SCRIPT" record-live-topology --repo-root "$REPO" --state-root "$STATE" --task-id "$STATE_TASK" --domain gptch.cloud --evidence-file "$LIVE_EVIDENCE" >/dev/null
expect_failure 'live topology evidence is stale' bash "$CONTROL_SCRIPT" assert-live-ready --repo-root "$REPO" --state-root "$STATE" --task-id "$STATE_TASK" --domain gptch.cloud --max-age-seconds 60

expect_failure 'duplicate matrix domain: gptch.cloud' bash "$CONTROL_SCRIPT" prepare-matrix --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --task-prefix duplicate --source-ref "$PARENT_COMMIT" --domains gptch.cloud,gptch.cloud

ORPHAN_TASK='orphan'
git -C "$REPO" worktree add --detach "$WORKTREES/$ORPHAN_TASK" "$PARENT_COMMIT" >/dev/null
expect_failure 'release worktree already exists without a task manifest' bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$ORPHAN_TASK" --domain artworkers.online --source-ref "$PARENT_COMMIT"

CLOSED_TASK='closed-task'
CLOSED_MANIFEST="$STATE/$CLOSED_TASK/process.md"
bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$CLOSED_TASK" --domain artworkers.online --source-ref "$PARENT_COMMIT" >/dev/null
for phase in composite-prepared local-preparation-verified live-discovery-recorded build-host-preflight artifacts-built production-authorized production-loaded-verified candidates-healthy cutover-complete public-accepted closed; do
    bash "$SCRIPT_DIR/release-state.sh" transition --manifest "$CLOSED_MANIFEST" --to "$phase" --evidence "test:$phase" >/dev/null
done
expect_failure 'task id is already complete at phase closed' bash "$CONTROL_SCRIPT" prepare-worktree --repo-root "$REPO" --state-root "$STATE" --worktree-root "$WORKTREES" --artifact-root "$TEST_ROOT/artifacts" --task-id "$CLOSED_TASK" --domain artworkers.online --source-ref "$PARENT_COMMIT"

printf 'image release-control tests passed\n'
