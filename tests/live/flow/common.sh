#!/usr/bin/env bash
# Faixa B · flow — shared fixture pieces. Sourced by the three fixture-*.sh; never run on its own.

# write_settings <work-dir> <hooks-dir> <hooklog>
# Registers ALL FIVE shipped hooks headlessly, plus a probe that logs every SessionStart source.
write_settings() {
  local work="$1" hooks="$2" hooklog="$3"
  cat > "$work/settings.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash '$hooks/sdd-session-start.sh'" },
          { "type": "command", "command": "jq -r '\"SESSIONSTART source=\" + (.source // \"?\")' >> '$hooklog'" }
        ] }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash '$hooks/sdd-enforce-test-first.sh'" },
          { "type": "command", "command": "bash '$hooks/sdd-warn-landed-test-edit.sh'" },
          { "type": "command", "command": "bash '$hooks/sdd-guard-issue-branch.sh'" }
        ] }
    ],
    "SubagentStop": [
      { "matcher": "*",
        "hooks": [ { "type": "command", "command": "bash '$hooks/sdd-verify-subagent.sh'" } ] }
    ]
  }
}
EOF
}

# write_cursor <progress-path> <phase> <doing> <next> <stop-reason> [worklog-line…]
write_cursor() {
  local p="$1" phase="$2" doing="$3" next="$4" stop="$5"; shift 5
  { printf '# PROGRESS — calc\n\n'
    printf '<!-- SDD-CURSOR -->\n- Phase: %s\n- Doing: %s\n- Next: %s\n- Stop-reason: %s\n<!-- /SDD-CURSOR -->\n\n' \
      "$phase" "$doing" "$next" "$stop"
    printf '## Worklog\n'
    if [ "$#" -eq 0 ]; then printf -- '- (empty)\n'; else printf -- '- %s\n' "$@"; fi
  } > "$p"
}

# has_test_only_commit <repo> <ref>
# True when some commit on <ref> touched ONLY test files — the durable trace of the test-first two-commit
# rule. A plain for-loop on purpose: a `git log | while read` runs in a subshell, so a `break`/`exit` in
# there cannot report back and the assertion would silently always pass.
has_test_only_commit() {
  local repo="$1" ref="$2" c files
  for c in $(git -C "$repo" log "$ref" --format=%H 2>/dev/null); do
    files="$(git -C "$repo" show --name-only --format= "$c" 2>/dev/null | grep -v '^$')"
    [ -n "$files" ] || continue
    if printf '%s\n' "$files" | grep -qiE '(^|/)tests?/' && ! printf '%s\n' "$files" | grep -q 'src/'; then
      return 0
    fi
  done
  return 1
}

# run_turn <out-file> <sim-var-name> <claude-args…>
# Runs one headless `claude` turn — unless SKIP_MODEL=1, in which case it runs the shell held in the named
# SIM_* variable instead. That seam exists for selftest.sh, which drives every assertion in this suite
# against a fabricated end state to prove they CAN pass. Live runs never set SKIP_MODEL.
run_turn() {
  local out="$1" simvar="$2"; shift 2
  if [ "${SKIP_MODEL:-0}" = 1 ]; then
    : > "$out"; eval "${!simvar:-:}"; return 0
  fi
  ( cd "$PROJ" && claude --print --verbose --output-format stream-json \
      --dangerously-skip-permissions \
      --plugin-dir "$PLUGIN_DIR" --settings "$SETTINGS" --model "$MODEL" \
      "$@" > "$out" 2>>"$WORK/stderr.txt" )
}

# git_init <proj>  : main + develop, one seeded commit of everything present.
git_init() {
  local d="$1"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t; git -C "$d" config user.name "sdd test"
  git -C "$d" add -A; git -C "$d" commit -qm "chore: validated baselines + profile"
  git -C "$d" branch develop; git -C "$d" checkout -q develop
}
