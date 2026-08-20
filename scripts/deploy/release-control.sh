#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_SCRIPT="$SCRIPT_DIR/release-state.sh"
RELEASE_WORKTREE_ROOT="${RELEASE_WORKTREE_ROOT:-$REPO_ROOT/.release-worktrees}"
RELEASE_ARTIFACT_ROOT="${RELEASE_ARTIFACT_ROOT:-$REPO_ROOT/.release-artifacts}"
STATE_ROOT="${RELEASE_STATE_ROOT:-$REPO_ROOT/.agents/state/tasks}"
CANVAS_PATH="vendor/infinite-canvas"

TASK_ID=""
DOMAIN=""
SOURCE_REF=""
PHASE=""
TASK_PREFIX=""
MATRIX_DOMAINS=""
EVIDENCE_FILE=""
MAX_AGE_SECONDS="${LIVE_TOPOLOGY_MAX_AGE_SECONDS:-1800}"

die() {
    printf 'release-control: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  scripts/deploy/release-control.sh profile --domain <gptch.cloud|artworkers.online|aiunify.xyz>
  scripts/deploy/release-control.sh prepare-worktree --task-id <id> --domain <domain> --source-ref <40-char-sha>
  scripts/deploy/release-control.sh prepare-matrix --task-prefix <prefix> --source-ref <40-char-sha> [--domains <csv>]
  scripts/deploy/release-control.sh prepare-composite --task-id <id> --domain <domain>
  scripts/deploy/release-control.sh dry-run --task-id <id> --phase local-preparation
  scripts/deploy/release-control.sh record-live-topology --task-id <id> --domain <domain> --evidence-file <path>
  scripts/deploy/release-control.sh live-status --task-id <id> --domain <domain> [--max-age-seconds <seconds>]
  scripts/deploy/release-control.sh assert-live-ready --task-id <id> --domain <domain> [--max-age-seconds <seconds>]

This controller only prepares local source evidence. It never builds images,
contacts production, transfers archives, starts containers, or changes Nginx.
EOF
}

require_value() {
    [ -n "${2:-}" ] || die "missing value for $1"
}

parse_common_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --task-id)
                require_value "$1" "${2:-}"
                TASK_ID="$2"
                shift 2
                ;;
            --domain)
                require_value "$1" "${2:-}"
                DOMAIN="$2"
                shift 2
                ;;
            --source-ref)
                require_value "$1" "${2:-}"
                SOURCE_REF="$2"
                shift 2
                ;;
            --phase)
                require_value "$1" "${2:-}"
                PHASE="$2"
                shift 2
                ;;
            --evidence-file)
                require_value "$1" "${2:-}"
                EVIDENCE_FILE="$2"
                shift 2
                ;;
            --max-age-seconds)
                require_value "$1" "${2:-}"
                MAX_AGE_SECONDS="$2"
                shift 2
                ;;
            --repo-root)
                require_value "$1" "${2:-}"
                REPO_ROOT="$2"
                shift 2
                ;;
            --state-root)
                require_value "$1" "${2:-}"
                STATE_ROOT="$2"
                shift 2
                ;;
            --worktree-root)
                require_value "$1" "${2:-}"
                RELEASE_WORKTREE_ROOT="$2"
                shift 2
                ;;
            --artifact-root)
                require_value "$1" "${2:-}"
                RELEASE_ARTIFACT_ROOT="$2"
                shift 2
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

require_repo_root() {
    REPO_ROOT="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)" || die "repository root does not exist: $REPO_ROOT"
    local actual_root
    actual_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)" || die "repository root is not a Git worktree: $REPO_ROOT"
    actual_root="$(cd "$actual_root" && pwd -P)"
    [ "$actual_root" = "$REPO_ROOT" ] || die "repository root must be the Git worktree root"
}

parse_matrix_args() {
    TASK_PREFIX=""
    SOURCE_REF=""
    MATRIX_DOMAINS="gptch.cloud,artworkers.online,aiunify.xyz"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --task-prefix)
                require_value "$1" "${2:-}"
                TASK_PREFIX="$2"
                shift 2
                ;;
            --source-ref)
                require_value "$1" "${2:-}"
                SOURCE_REF="$2"
                shift 2
                ;;
            --domains)
                require_value "$1" "${2:-}"
                MATRIX_DOMAINS="$2"
                shift 2
                ;;
            --repo-root)
                require_value "$1" "${2:-}"
                REPO_ROOT="$2"
                shift 2
                ;;
            --state-root)
                require_value "$1" "${2:-}"
                STATE_ROOT="$2"
                shift 2
                ;;
            --worktree-root)
                require_value "$1" "${2:-}"
                RELEASE_WORKTREE_ROOT="$2"
                shift 2
                ;;
            --artifact-root)
                require_value "$1" "${2:-}"
                RELEASE_ARTIFACT_ROOT="$2"
                shift 2
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

validate_task() {
    [[ "$TASK_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "task id must contain only letters, numbers, dot, underscore, or dash"
}

validate_task_prefix() {
    [[ "$TASK_PREFIX" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$ ]] || die "task prefix must contain only letters, numbers, dot, underscore, or dash"
}

validate_domain() {
    case "$DOMAIN" in
        gptch.cloud|artworkers.online|aiunify.xyz) ;;
        *) die "unsupported Image domain: $DOMAIN" ;;
    esac
}

validate_source_ref() {
    [[ "$SOURCE_REF" =~ ^[0-9a-f]{40}$ ]] || die "source ref must be an immutable 40-character commit SHA"
}

task_state_dir() {
    printf '%s/%s' "$STATE_ROOT" "$TASK_ID"
}

task_worktree() {
    printf '%s/%s' "$RELEASE_WORKTREE_ROOT" "$TASK_ID"
}

task_artifact_dir() {
    printf '%s/%s' "$RELEASE_ARTIFACT_ROOT" "$TASK_ID"
}

manifest_path() {
    printf '%s/process.md' "$(task_state_dir)"
}

domain_origin() {
    validate_domain
    printf 'https://%s' "$DOMAIN"
}

release_ref_name() {
    local domain="$1" task_id="$2" parent_sha="$3"
    printf 'refs/image-release/%s/%s/%s' "$domain" "$task_id" "$parent_sha"
}

ensure_release_ref() {
    local domain="$1" task_id="$2" parent_sha="$3" release_ref current
    release_ref="$(release_ref_name "$domain" "$task_id" "$parent_sha")"
    current="$(git -C "$REPO_ROOT" rev-parse --verify "$release_ref" 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "$parent_sha" ]; then
        die "release ref already points to a different commit: $release_ref"
    fi
    if [ -z "$current" ]; then
        git -C "$REPO_ROOT" update-ref -m "image release $domain $task_id" "$release_ref" "$parent_sha"
    fi
    printf '%s' "$release_ref"
}

assert_pushed_main_commit() {
    local source_sha remote_sha
    source_sha="$(git -C "$REPO_ROOT" rev-parse --verify "$SOURCE_REF^{commit}")"
    [ "$source_sha" = "$SOURCE_REF" ] || die "source ref does not resolve to the requested immutable SHA"
    remote_sha="$(git -C "$REPO_ROOT" ls-remote origin refs/heads/main | awk 'NR == 1 { print $1 }')"
    [ -n "$remote_sha" ] || die "could not resolve origin/main"
    git -C "$REPO_ROOT" merge-base --is-ancestor "$source_sha" "$remote_sha" || die "source commit is not contained in origin/main"
}

assert_shell_domain_build_contract() {
    local source_dir="$1"
    grep -qE '^[[:space:]]*ARG VITE_BASE=' "$source_dir/Dockerfile" || die "Shell Dockerfile must declare VITE_BASE"
    grep -qE '^[[:space:]]*ARG VITE_FIXED_API_BASE_URL' "$source_dir/Dockerfile" || die "Shell Dockerfile must declare VITE_FIXED_API_BASE_URL"
    grep -qE '^[[:space:]]*ENV VITE_FIXED_API_BASE_URL=\$\{VITE_FIXED_API_BASE_URL\}' "$source_dir/Dockerfile" || die "Shell Dockerfile must export VITE_FIXED_API_BASE_URL"
}

canvas_gitlink_sha() {
    local parent_sha="$1" entry
    entry="$(git -C "$REPO_ROOT" ls-tree "$parent_sha" "$CANVAS_PATH")"
    [[ "$entry" =~ ^160000[[:space:]]commit[[:space:]]([0-9a-f]{40}) ]] || die "missing Canvas gitlink at $CANVAS_PATH"
    printf '%s' "${BASH_REMATCH[1]}"
}

assert_canvas_openai_base() {
    local canvas_dir="$1"
    python3 "$SCRIPT_DIR/validate-canvas-contract.py" "$canvas_dir" "$DOMAIN" || die "Canvas source failed semantic domain contract"
    grep -qE '^[[:space:]]*ARG VITE_FIXED_API_BASE_URL=' "$canvas_dir/Dockerfile" || die "Canvas Dockerfile must declare VITE_FIXED_API_BASE_URL"
    grep -qE '^[[:space:]]*ENV VITE_FIXED_API_BASE_URL=\$\{VITE_FIXED_API_BASE_URL\}' "$canvas_dir/Dockerfile" || die "Canvas Dockerfile must export VITE_FIXED_API_BASE_URL"
}

assert_canvas_subpath_contract() {
    local canvas_dir="$1"
    grep -qF 'ARG VITE_BASE=/canvas/' "$canvas_dir/Dockerfile" || die "Canvas Dockerfile must default VITE_BASE to /canvas/"
    grep -qF 'base: appBase,' "$canvas_dir/web/vite.config.ts" || die "Canvas Vite config must use the normalized base"
    grep -qF 'basename: import.meta.env.BASE_URL' "$canvas_dir/web/src/router.tsx" || die "Canvas router must use the Vite base as basename"
}

git_common_dir() {
    git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || die "cannot resolve Git common directory: $1"
}

assert_detached_release_worktree() {
    local worktree="$1" canonical_worktree
    canonical_worktree="$(cd "$worktree" && pwd -P)" || die "prepared worktree does not exist: $worktree"
    [ "$canonical_worktree" != "$REPO_ROOT" ] || die "attached checkout cannot be used as a release worktree"
    git -C "$worktree" symbolic-ref -q HEAD >/dev/null && die "prepared worktree must be detached; use a new task id for a new release"
    [ "$(git_common_dir "$worktree")" = "$(git_common_dir "$REPO_ROOT")" ] || die "prepared worktree belongs to a different Git repository"
}

assert_task_is_active_or_new() {
    local parent_sha="$1" manifest existing_domain existing_parent state phase status
    manifest="$(manifest_path)"

    if [ -e "$manifest" ]; then
        [ -f "$manifest" ] || die "task manifest is not a regular file: $manifest"
        # Codex initializes task-local process.md before this controller owns it.
        # Accept only that plain handoff shape for first release initialization.
        if ! grep -Fqx '## Release State' "$manifest" && \
            ! grep -Fqx '## Source' "$manifest" && \
            ! grep -Fqx '## Composite Archive' "$manifest" && \
            ! grep -Fqx '## Live Topology' "$manifest" && \
            ! grep -Fqx '## Artifacts' "$manifest" && \
            ! grep -Fqx '## Production' "$manifest"; then
            return
        fi
        state="$("$STATE_SCRIPT" show --manifest "$manifest")" || die "existing task state cannot be read; use a new task id or repair task state"
        phase="$(printf '%s\n' "$state" | sed -n 's/^current_phase=//p')"
        status="$(printf '%s\n' "$state" | sed -n 's/^phase_status=//p')"
        [ "$status" = active ] || die "task id is already $status at phase $phase; use a new task id for a new release"
        existing_domain="$(read_manifest_value 'Domain')"
        existing_parent="$(read_manifest_value 'Parent Commit')"
        [ "$existing_domain" = "$DOMAIN" ] || die "active task domain does not match requested domain; use a new task id"
        [ "$existing_parent" = "$parent_sha" ] || die "active task parent commit does not match requested source; use a new task id"
    elif [ -e "$(task_state_dir)" ]; then
        die "task state directory already exists without a task manifest; use a new task id or repair task state"
    fi

    if [ -e "$(task_worktree)" ] && [ ! -f "$manifest" ]; then
        die "release worktree already exists without a task manifest; use a new task id or inspect the orphaned worktree"
    fi
}

assert_prepared_pair() {
    local worktree="$1" parent_sha="$2" canvas_sha
    [ -d "$worktree/.git" ] || [ -f "$worktree/.git" ] || die "prepared worktree is missing: $worktree"
    assert_detached_release_worktree "$worktree"
    [ "$(git -C "$worktree" rev-parse HEAD)" = "$parent_sha" ] || die "prepared worktree parent commit does not match manifest"
    canvas_sha="$(canvas_gitlink_sha "$parent_sha")"
    [ -d "$worktree/$CANVAS_PATH/.git" ] || [ -f "$worktree/$CANVAS_PATH/.git" ] || die "Canvas submodule is not initialized"
    [ "$(git -C "$worktree/$CANVAS_PATH" rev-parse HEAD)" = "$canvas_sha" ] || die "Canvas checkout does not match parent gitlink"
    [ -z "$(git -C "$worktree" status --porcelain --ignore-submodules=none)" ] || die "prepared worktree is dirty"
    [ -z "$(git -C "$worktree/$CANVAS_PATH" status --porcelain)" ] || die "Canvas checkout is dirty"
    assert_shell_domain_build_contract "$worktree"
    assert_canvas_openai_base "$worktree/$CANVAS_PATH"
    assert_canvas_subpath_contract "$worktree/$CANVAS_PATH"
}

assert_manifest_domain() {
    local manifest_domain
    manifest_domain="$(read_manifest_value 'Domain')"
    [ "$manifest_domain" = "$DOMAIN" ] || die "manifest domain does not match requested domain"
}

assert_manifest_release_ref() {
    local parent_sha release_ref
    parent_sha="$(read_manifest_value 'Parent Commit')"
    release_ref="$(read_manifest_value 'Release Ref')"
    [ "$release_ref" = "$(release_ref_name "$DOMAIN" "$TASK_ID" "$parent_sha")" ] || die "manifest release ref does not match the selected domain"
    [ "$(git -C "$REPO_ROOT" rev-parse --verify "$release_ref")" = "$parent_sha" ] || die "release ref does not point to the manifest parent commit"
}

read_manifest_value() {
    local label="$1"
    sed -n "s/^- ${label}: //p" "$(manifest_path)" | head -n 1
}

live_topology_value() {
    local label="$1"
    awk -v label="$label" '
        /^## Live Topology$/ { capture = 1; next }
        capture && /^## Artifacts$/ { exit }
        capture && index($0, "- " label ": ") == 1 {
            print substr($0, length(label) + 5)
            exit
        }
    ' "$(manifest_path)"
}

release_state_phase() {
    "$STATE_SCRIPT" show --manifest "$(manifest_path)" | sed -n 's/^current_phase=//p'
}

initialize_release_state() {
    local parent_sha="$1" canvas_sha="$2"
    "$STATE_SCRIPT" init --manifest "$(manifest_path)" --phase source-prepared --evidence "source-pair:$parent_sha:$canvas_sha" >/dev/null
}

assert_release_state_phase() {
    local expected_phase="$1" action="$2" current
    current="$(release_state_phase)"
    [ "$current" = "$expected_phase" ] || die "$action is not allowed at release phase $current; expected $expected_phase"
    "$STATE_SCRIPT" assert --manifest "$(manifest_path)" --phase "$expected_phase" --status active >/dev/null
}

assert_release_state_transitionable() {
    local from_phase="$1" to_phase="$2" action="$3" current
    current="$(release_state_phase)"
    case "$current" in
        "$from_phase"|"$to_phase")
            "$STATE_SCRIPT" assert --manifest "$(manifest_path)" --phase "$current" --status active >/dev/null
            ;;
        *)
            die "$action is not allowed at release phase $current; expected $from_phase or $to_phase"
            ;;
    esac
}

advance_release_state() {
    local from_phase="$1" to_phase="$2" evidence="$3" action="$4" current
    current="$(release_state_phase)"
    case "$current" in
        "$from_phase")
            "$STATE_SCRIPT" transition --manifest "$(manifest_path)" --to "$to_phase" --evidence "$evidence" >/dev/null
            ;;
        "$to_phase")
            "$STATE_SCRIPT" assert --manifest "$(manifest_path)" --phase "$to_phase" --status active >/dev/null
            ;;
        *)
            die "$action is not allowed at release phase $current; expected $from_phase or $to_phase"
            ;;
    esac
}

write_manifest() {
    local parent_sha="$1" canvas_sha="$2" worktree="$3" artifact_dir="$4" archive="$artifact_dir/source-composite.tar"
    local archive_sha="pending" shell_dockerfile_sha canvas_dockerfile_sha origin release_ref existing_state="" existing_live_topology=""
    shell_dockerfile_sha="$(shasum -a 256 "$worktree/Dockerfile" | awk '{print $1}')"
    canvas_dockerfile_sha="$(shasum -a 256 "$worktree/$CANVAS_PATH/Dockerfile" | awk '{print $1}')"
    [ -f "$archive" ] && archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
    origin="$(domain_origin)"
    release_ref="$(release_ref_name "$DOMAIN" "$TASK_ID" "$parent_sha")"
    mkdir -p "$(task_state_dir)"
    if [ -f "$(manifest_path)" ]; then
        existing_state="$(awk '/^## Release State$/ { state = 1 } state { print }' "$(manifest_path)")"
        existing_live_topology="$(awk '/^## Live Topology$/ { capture = 1 } capture && /^## Artifacts$/ { exit } capture { print }' "$(manifest_path)")"
    fi
    cat >"$(manifest_path)" <<EOF
# $DOMAIN Image Release Manifest

## Source
- Domain: $DOMAIN
- Source Line: main
- Parent Commit: $parent_sha
- Canvas Gitlink Commit: $canvas_sha
- Release Ref: $release_ref
- Shell Build Args: VITE_BASE=/image/,VITE_FIXED_API_BASE_URL=$origin
- Canvas Build Args: VITE_BASE=/canvas/,VITE_FIXED_API_BASE_URL=$origin
- Canvas API Base URL: $origin
- Canvas API Source: build-time:VITE_FIXED_API_BASE_URL
- Worktree: $worktree
- Shell Dockerfile SHA-256: $shell_dockerfile_sha
- Canvas Dockerfile SHA-256: $canvas_dockerfile_sha

## Composite Archive
- Path: $archive
- SHA-256: $archive_sha

## Profile
- Documented Status: unverified
- Allowed Routes: /image/, /canvas/, /canvas-uploads/

EOF
    if [ -n "$existing_live_topology" ]; then
        printf '%s\n' "$existing_live_topology" >>"$(manifest_path)"
    else
        cat >>"$(manifest_path)" <<EOF

## Live Topology
- Live Status: not-recorded
- Discovery Domain: pending
- Evidence SHA-256: pending
- Observed At: pending
- Shell Blue/Green: unverified
- Canvas Blue/Green: unverified
- Uploads Blue/Green: unverified
- MinIO Isolation: unverified

EOF
    fi
    cat >>"$(manifest_path)" <<EOF

## Artifacts
- Shell Image: pending
- Canvas Image: pending
- Uploads Edge Image: unchanged unless explicitly included in the release plan

## Production
- Candidate Topology: pending discovery
- Rollback: no production action has been authorized or performed
EOF
    [ -z "$existing_state" ] || printf '\n%s\n' "$existing_state" >>"$(manifest_path)"
}

prepare_worktree() {
    require_repo_root
    validate_task
    validate_domain
    validate_source_ref
    assert_pushed_main_commit

    local parent_sha canvas_sha worktree artifact_dir
    parent_sha="$(git -C "$REPO_ROOT" rev-parse "$SOURCE_REF")"
    canvas_sha="$(canvas_gitlink_sha "$parent_sha")"
    worktree="$(task_worktree)"
    artifact_dir="$(task_artifact_dir)"
    assert_task_is_active_or_new "$parent_sha"
    mkdir -p "$RELEASE_WORKTREE_ROOT" "$artifact_dir"

    if [ -e "$worktree" ]; then
        assert_prepared_pair "$worktree" "$parent_sha"
    else
        git -C "$REPO_ROOT" worktree add --detach "$worktree" "$parent_sha"
        git -C "$worktree" submodule update --init --recursive "$CANVAS_PATH"
        assert_prepared_pair "$worktree" "$parent_sha"
    fi

    ensure_release_ref "$DOMAIN" "$TASK_ID" "$parent_sha" >/dev/null
    write_manifest "$parent_sha" "$canvas_sha" "$worktree" "$artifact_dir"
    initialize_release_state "$parent_sha" "$canvas_sha"
    printf 'prepared_worktree=%s\nparent_commit=%s\ncanvas_commit=%s\nmanifest=%s\n' "$worktree" "$parent_sha" "$canvas_sha" "$(manifest_path)"
}

profile() {
    require_repo_root
    validate_domain
    local origin
    origin="$(domain_origin)"
    printf 'domain=%s\norigin=%s\nallowed_paths=/image/,/canvas/,/canvas-uploads/\n' "$DOMAIN" "$origin"
    printf 'shell_build_args=VITE_BASE=/image/,VITE_FIXED_API_BASE_URL=%s\n' "$origin"
    printf 'canvas_build_args=VITE_BASE=/canvas/,VITE_FIXED_API_BASE_URL=%s\n' "$origin"
    printf 'documented_status=unverified\nlive_status=not-recorded\ntopology_gate=requires-fresh-live-discovery\nremote_actions=none\n'
}

evidence_value() {
    local key="$1" count
    count="$(grep -c "^${key}=" "$EVIDENCE_FILE" || true)"
    [ "$count" = 1 ] || die "live topology evidence must contain exactly one $key entry"
    sed -n "s/^${key}=//p" "$EVIDENCE_FILE"
}

validate_topology_check() {
    case "$1" in
        ready|not-ready|unknown) ;;
        *) die "live topology checks must be ready, not-ready, or unknown" ;;
    esac
}

validate_observed_at() {
    local observed_at="$1"
    [[ "$observed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "Observed At must be an RFC 3339 UTC timestamp"
    python3 - "$observed_at" <<'PY' >/dev/null || die "Observed At is not a valid UTC timestamp"
from datetime import datetime
import sys

datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
PY
}

topology_age_seconds() {
    python3 - "$1" <<'PY'
from datetime import datetime, timezone
import sys

observed_at = datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
print(int((datetime.now(timezone.utc) - observed_at).total_seconds()))
PY
}

validate_max_age_seconds() {
    [[ "$MAX_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "max age seconds must be a positive integer"
}

write_live_topology() {
    local status="$1" discovery_domain="$2" evidence_sha="$3" observed_at="$4"
    local shell_status="$5" canvas_status="$6" uploads_status="$7" minio_status="$8"
    local prefix suffix tmp manifest_dir
    manifest_dir="$(cd "$(dirname "$(manifest_path)")" && pwd -P)"
    prefix="$(mktemp "$manifest_dir/.live-topology-prefix.XXXXXX")"
    suffix="$(mktemp "$manifest_dir/.live-topology-suffix.XXXXXX")"
    tmp="$(mktemp "$manifest_dir/.live-topology.XXXXXX")"
    trap "rm -f '$prefix' '$suffix' '$tmp'" EXIT

    awk '/^## Live Topology$/ { exit } { print }' "$(manifest_path)" >"$prefix"
    awk '/^## Artifacts$/ { copy = 1 } copy { print }' "$(manifest_path)" >"$suffix"
    {
        cat "$prefix"
        printf '\n## Live Topology\n'
        printf '%s\n' "- Live Status: $status"
        printf '%s\n' "- Discovery Domain: $discovery_domain"
        printf '%s\n' "- Evidence SHA-256: $evidence_sha"
        printf '%s\n' "- Observed At: $observed_at"
        printf '%s\n' "- Shell Blue/Green: $shell_status"
        printf '%s\n' "- Canvas Blue/Green: $canvas_status"
        printf '%s\n' "- Uploads Blue/Green: $uploads_status"
        printf '%s\n' "- MinIO Isolation: $minio_status"
        printf '\n'
        cat "$suffix"
    } >"$tmp"
    mv "$tmp" "$(manifest_path)"
    rm -f "$prefix" "$suffix"
    trap - EXIT
}

record_live_topology() {
    require_repo_root
    validate_task
    validate_domain
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    assert_manifest_domain
    assert_release_state_transitionable local-preparation-verified live-discovery-recorded record-live-topology
    [ -n "$EVIDENCE_FILE" ] || die "--evidence-file is required"
    [ -f "$EVIDENCE_FILE" ] || die "live topology evidence does not exist: $EVIDENCE_FILE"

    local discovery_domain observed_at shell_status canvas_status uploads_status minio_status evidence_sha live_status
    discovery_domain="$(evidence_value domain)"
    [ "$discovery_domain" = "$DOMAIN" ] || die "live topology evidence domain does not match requested domain"
    observed_at="$(evidence_value observed_at)"
    validate_observed_at "$observed_at"
    shell_status="$(evidence_value shell_bluegreen)"
    canvas_status="$(evidence_value canvas_bluegreen)"
    uploads_status="$(evidence_value uploads_bluegreen)"
    minio_status="$(evidence_value minio_isolation)"
    validate_topology_check "$shell_status"
    validate_topology_check "$canvas_status"
    validate_topology_check "$uploads_status"
    validate_topology_check "$minio_status"
    evidence_sha="$(shasum -a 256 "$EVIDENCE_FILE" | awk '{print $1}')"
    live_status=not-ready
    if [ "$shell_status" = ready ] && [ "$canvas_status" = ready ] && [ "$uploads_status" = ready ] && [ "$minio_status" = ready ]; then
        live_status=ready-for-bluegreen
    fi
    write_live_topology "$live_status" "$discovery_domain" "$evidence_sha" "$observed_at" "$shell_status" "$canvas_status" "$uploads_status" "$minio_status"
    advance_release_state local-preparation-verified live-discovery-recorded "live-topology-sha256:$evidence_sha" record-live-topology
    printf 'documented_status=%s\nlive_status=%s\nlive_evidence_sha256=%s\nremote_actions=none\n' "$(read_manifest_value 'Documented Status')" "$live_status" "$evidence_sha"
}

live_status() {
    require_repo_root
    validate_task
    validate_domain
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    assert_manifest_domain
    printf 'documented_status=%s\nlive_status=%s\nlive_evidence_sha256=%s\nlive_observed_at=%s\n' \
        "$(read_manifest_value 'Documented Status')" "$(live_topology_value 'Live Status')" "$(live_topology_value 'Evidence SHA-256')" "$(live_topology_value 'Observed At')"
}

assert_live_ready() {
    require_repo_root
    validate_task
    validate_domain
    validate_max_age_seconds
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    assert_manifest_domain

    local live_domain live_status evidence_sha observed_at age_seconds check
    live_domain="$(live_topology_value 'Discovery Domain')"
    live_status="$(live_topology_value 'Live Status')"
    evidence_sha="$(live_topology_value 'Evidence SHA-256')"
    observed_at="$(live_topology_value 'Observed At')"
    [ "$live_domain" = "$DOMAIN" ] || die "live topology discovery domain does not match requested domain"
    [ "$live_status" = ready-for-bluegreen ] || die "live topology status is $live_status; fresh discovery must report ready-for-bluegreen"
    [[ "$evidence_sha" =~ ^[0-9a-f]{64}$ ]] || die "live topology evidence SHA-256 is missing or invalid"
    validate_observed_at "$observed_at"
    age_seconds="$(topology_age_seconds "$observed_at")"
    [ "$age_seconds" -ge 0 ] || die "live topology observation is in the future"
    [ "$age_seconds" -le "$MAX_AGE_SECONDS" ] || die "live topology evidence is stale: ${age_seconds}s exceeds ${MAX_AGE_SECONDS}s"
    for check in 'Shell Blue/Green' 'Canvas Blue/Green' 'Uploads Blue/Green' 'MinIO Isolation'; do
        [ "$(live_topology_value "$check")" = ready ] || die "live topology check is not ready: $check"
    done
    printf 'documented_status=%s\nlive_status=%s\nlive_evidence_sha256=%s\nlive_evidence_age_seconds=%s\ntopology_gate=ready-for-bluegreen\n' \
        "$(read_manifest_value 'Documented Status')" "$live_status" "$evidence_sha" "$age_seconds"
}

prepare_matrix() {
    require_repo_root
    validate_task_prefix
    validate_source_ref
    assert_pushed_main_commit

    local parent_sha domain task_id
    local -a domains
    IFS=',' read -r -a domains <<< "$MATRIX_DOMAINS"
    [ "${#domains[@]}" -gt 0 ] || die "domains must not be empty"
    local seen=,
    for domain in "${domains[@]}"; do
        [ -n "$domain" ] || die "domains must not contain an empty item"
        DOMAIN="$domain"
        validate_domain
        case "$seen" in
            *,"$domain",*) die "duplicate matrix domain: $domain" ;;
        esac
        seen="$seen$domain,"
    done

    parent_sha="$(git -C "$REPO_ROOT" rev-parse "$SOURCE_REF")"
    for domain in "${domains[@]}"; do
        TASK_ID="${TASK_PREFIX}-${domain//./-}"
        DOMAIN="$domain"
        SOURCE_REF="$parent_sha"
        prepare_worktree
    done
}

prepare_composite() {
    require_repo_root
    validate_task
    validate_domain
    local parent_sha canvas_sha worktree artifact_dir context archive
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    assert_manifest_domain
    assert_manifest_release_ref
    assert_release_state_phase source-prepared prepare-composite
    parent_sha="$(read_manifest_value 'Parent Commit')"
    canvas_sha="$(read_manifest_value 'Canvas Gitlink Commit')"
    worktree="$(read_manifest_value 'Worktree')"
    [ -n "$parent_sha" ] && [ -n "$canvas_sha" ] && [ -n "$worktree" ] || die "release manifest is incomplete"
    assert_prepared_pair "$worktree" "$parent_sha"
    [ "$(canvas_gitlink_sha "$parent_sha")" = "$canvas_sha" ] || die "manifest Canvas commit does not match parent gitlink"

    artifact_dir="$(task_artifact_dir)"
    context="$artifact_dir/source-composite"
    archive="$artifact_dir/source-composite.tar"
    rm -rf "$context" "$archive"
    mkdir -p "$context/$CANVAS_PATH"
    git -C "$worktree" archive "$parent_sha" | tar -xf - -C "$context"
    git -C "$worktree/$CANVAS_PATH" archive "$canvas_sha" | tar -xf - -C "$context/$CANVAS_PATH"
    tar -cf "$archive" -C "$context" .
    write_manifest "$parent_sha" "$canvas_sha" "$worktree" "$artifact_dir"
    advance_release_state source-prepared composite-prepared "archive-sha256:$(shasum -a 256 "$archive" | awk '{print $1}')" prepare-composite
    printf 'composite_archive=%s\nsha256=%s\n' "$archive" "$(shasum -a 256 "$archive" | awk '{print $1}')"
}

dry_run() {
    require_repo_root
    validate_task
    [ "$PHASE" = "local-preparation" ] || die "only --phase local-preparation is permitted; remote release phases require a ready profile and separate production authorization"
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    assert_release_state_phase composite-prepared dry-run
    local parent_sha worktree manifest_domain
    parent_sha="$(read_manifest_value 'Parent Commit')"
    worktree="$(read_manifest_value 'Worktree')"
    manifest_domain="$(read_manifest_value 'Domain')"
    [ -n "$parent_sha" ] && [ -n "$worktree" ] || die "release manifest is incomplete"
    DOMAIN="$manifest_domain"
    validate_domain
    assert_manifest_release_ref
    assert_prepared_pair "$worktree" "$parent_sha"
    advance_release_state composite-prepared local-preparation-verified "prepared-pair:$parent_sha:$(canvas_gitlink_sha "$parent_sha")" dry-run
    printf 'dry_run=local-preparation\ntask_id=%s\ndomain=%s\nparent_commit=%s\ncanvas_commit=%s\ncurrent_phase=local-preparation-verified\nstatus=ready-for-build-host-preflight\nremote_actions=none\n' "$TASK_ID" "$DOMAIN" "$parent_sha" "$(canvas_gitlink_sha "$parent_sha")"
}

main() {
    local command="${1:-}"
    [ -n "$command" ] || {
        usage
        exit 1
    }
    shift
    case "$command" in
        profile)
            parse_common_args "$@"
            profile
            ;;
        prepare-worktree)
            parse_common_args "$@"
            prepare_worktree
            ;;
        prepare-matrix)
            parse_matrix_args "$@"
            prepare_matrix
            ;;
        prepare-composite)
            parse_common_args "$@"
            prepare_composite
            ;;
        dry-run)
            parse_common_args "$@"
            dry_run
            ;;
        record-live-topology)
            parse_common_args "$@"
            record_live_topology
            ;;
        live-status)
            parse_common_args "$@"
            live_status
            ;;
        assert-live-ready)
            parse_common_args "$@"
            assert_live_ready
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "unknown command: $command"
            ;;
    esac
}

main "$@"
