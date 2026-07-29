#!/usr/bin/env bash
# Faixa B · flow — shared fixture pieces. Sourced by the three fixture-*.sh; never run on its own.

# write_settings <work-dir> <hooks-dir> <hooklog> [subagent-decision-log] [read-log] [skill-log]
# Registers ALL FIVE shipped hooks headlessly, plus a probe that logs every SessionStart source.
#
# The optional 4th argument adds a LOG-ONLY duplicate of the SubagentStop verifier whose stdout goes to a
# file instead of to Claude. A hook cannot observe a sibling hook's verdict, and a `decision: block` never
# reaches the main transcript (it is fed back into the SUBAGENT), so a scenario asserting "the block fired"
# has nothing to read otherwise. The duplicate is safe because the verifier is a pure read of git + files.
#
# The optional 5th argument adds a PreToolUse(Read) probe that appends every file path the model (or a
# subagent) opens to a log — the seam the `bdd` scenario uses to prove /bdd routes to the RIGHT on-demand
# sibling and never loads the other mode's file. Kept free of `$`/backslashes for the JSON-in-heredoc reason
# noted below.
#
# The optional 6th argument adds a PreToolUse(Skill) probe that logs every skill NAME the model (or a
# subagent) invokes — the direct seam the `worker` scenario uses to prove a dispatched sdd-issue-worker
# actually invokes `/bdd` and `/tdd`, which a Read probe cannot see (the `/tdd` skill is self-contained in its
# SKILL.md and reads no sibling). Same `$`/backslash-free JSON-safety rule.
write_settings() {
  local work="$1" hooks="$2" hooklog="$3" sublog="${4:-}" readlog="${5:-}" skilllog="${6:-}"
  local sub_extra="" read_block="" skill_block=""
  # Logs one line per stop, ALWAYS — the verifier prints nothing when it allows, so appending its raw stdout
  # would leave an empty file for both "allowed every stop" and "never ran at all". The marker separates them.
  # Deliberately free of `$` and backslashes: this is a shell string embedded in a JSON string embedded in a
  # heredoc, and a `\$(…)` here once produced a settings.json that failed to parse — which silently disabled
  # EVERY hook for a whole live run, a failure that looks exactly like a well-behaved model.
  [ -n "$sublog" ] && sub_extra=",
          { \"type\": \"command\", \"command\": \"bash '$hooks/sdd-verify-subagent.sh' > '$sublog.tmp' 2>/dev/null; { printf 'STOP '; cat '$sublog.tmp'; echo; } >> '$sublog'; true\" }"
  # A PreToolUse(Read) probe — pure log, exit 0, its own matcher so it never touches the guards. Appends the
  # opened path; jq reads the hook payload on stdin. No `$`/backslash, same JSON-safety reason as above.
  [ -n "$readlog" ] && read_block=",
      { \"matcher\": \"Read\",
        \"hooks\": [ { \"type\": \"command\", \"command\": \"jq -r '.tool_input.file_path // .tool_input.path // empty' >> '$readlog'; true\" } ] }"
  # A PreToolUse(Skill) probe — logs the invoked skill name; own matcher, pure log, exit 0. Same JSON-safety.
  [ -n "$skilllog" ] && skill_block=",
      { \"matcher\": \"Skill\",
        \"hooks\": [ { \"type\": \"command\", \"command\": \"jq -r '.tool_input.skill // .tool_input.command // empty' >> '$skilllog'; true\" } ] }"
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
        ] }$read_block$skill_block
    ],
    "SubagentStop": [
      { "matcher": "*",
        "hooks": [ { "type": "command", "command": "bash '$hooks/sdd-verify-subagent.sh'" }$sub_extra ] }
    ]
  }
}
EOF
  # An invalid settings.json makes Claude Code load NO hooks at all, and a hookless run looks exactly like a
  # perfectly-behaved one — every behavioural assertion still passes, and the scenario silently tests nothing.
  # That happened once. Fail loudly here instead.
  if command -v jq >/dev/null 2>&1 && ! jq -e . "$work/settings.json" >/dev/null 2>&1; then
    echo "FATAL: generated $work/settings.json is not valid JSON — the run would load no hooks." >&2
    jq . "$work/settings.json" >&2 || true
    return 1
  fi
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

# test_only_commits <repo> <ref>  -> prints the hashes of every commit that touched ONLY test files.
# Same plain-loop reasoning as has_test_only_commit: never pipe `git log` into a `while read`.
test_only_commits() {
  local repo="$1" ref="$2" c files
  for c in $(git -C "$repo" log "$ref" --format=%H 2>/dev/null); do
    files="$(git -C "$repo" show --name-only --format= "$c" 2>/dev/null | grep -v '^$')"
    [ -n "$files" ] || continue
    if printf '%s\n' "$files" | grep -qiE '(^|/)tests?/' && ! printf '%s\n' "$files" | grep -q 'src/'; then
      printf '%s\n' "$c"
    fi
  done
}

# proves_red <repo> <ref> <test-cmd>
# The mechanical RED proof, with no reliance on what the model REPORTED. For each test-only commit on <ref>
# it reconstructs "the tests as committed, against the source as it was BEFORE them" (that commit's tree,
# with src/ restored from its parent) and runs the suite there. At least one such reconstruction must FAIL —
# otherwise the behaviour test never had a red to go green from.
#
# This is also the cheapest hollow-green detector: a test that ARRANGES what it asserts (registering the op
# inside the test, then asserting dispatch finds it) passes against the pre-implementation source, so the
# reconstruction goes green and this returns false.
proves_red() {
  local repo="$1" ref="$2" cmd="$3" c wt rc reds=0
  wt="$(mktemp -d)"
  for c in $(test_only_commits "$repo" "$ref"); do
    rm -rf "$wt"; git clone -q --no-local --shared "$repo" "$wt" 2>/dev/null || { rm -rf "$wt"; return 1; }
    git -C "$wt" checkout -q "$c" 2>/dev/null || continue
    git -C "$wt" rev-parse -q --verify "$c^" >/dev/null 2>&1 || continue
    git -C "$wt" checkout -q "$c^" -- src/ 2>/dev/null || true
    ( cd "$wt" && eval "$cmd" ) >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] && reds=$((reds+1))
  done
  rm -rf "$wt"
  [ "$reds" -gt 0 ]
}

# probe_delivered <repo> <ref> <probe.py>
# Runs an INDEPENDENT probe — written by the fixture, never seen by the model — against the delivered
# surface with the whole test suite REMOVED. The distinction it draws is the one no existing gate draws:
# "the suite is green" vs "the system works". A hollow green (setup living inside the test) satisfies the
# first and fails here, which is exactly the defect this suite exists to catch.
probe_delivered() {
  local repo="$1" ref="$2" probe="$3" wt rc
  wt="$(mktemp -d)"; rm -rf "$wt"
  git clone -q --no-local --shared --branch "$ref" "$repo" "$wt" 2>/dev/null || { rm -rf "$wt"; return 1; }
  rm -rf "$wt"/tests "$wt"/test
  ( cd "$wt" && PYTHONPATH=src python3 "$probe" ) >/dev/null 2>&1; rc=$?
  rm -rf "$wt"; return $rc
}

# had_checkpoint_in_history <repo> <ref> <issue-id>
# The inner-loop checkpoint is a MID-ISSUE resume point, not a permanent record: RECORD legitimately
# condenses the worklog once the phase closes, so a live run ends with the lines gone from the tip. The
# durable trace is in history — reading only the tip asks whether the loop tidied up, not whether it did TDD.
had_checkpoint_in_history() {
  local repo="$1" ref="$2" id="$3" c
  for c in $(git -C "$repo" log "$ref" --format=%H 2>/dev/null); do
    git -C "$repo" show "$c:docs/PROGRESS.md" 2>/dev/null \
      | grep -qiE "$id.*unit .*green|unit .*green.*$id" && return 0
  done
  return 1
}

# gate_probe <hooks-dir> <repo> <ref> <issue-id> <checkpoint-line|"">  -> prints "block" or "allow"
# Asks the SubagentStop verifier what it WOULD do for a worker claiming green on <issue-id>, against a
# disposable clone of the run's own artifacts — its backlog, its history — with the worklog rewritten to
# carry the given checkpoint line (or none).
#
# It runs on the integration branch, where the branch check exits early, so the only thing that can block is
# the inner-TDD checkpoint gate. That isolation is the whole point: it answers "is the gate ARMED against
# these artifacts?" without needing the model to have misbehaved, which is not something a prompt can
# reliably arrange. It is also the exact question the flat Faixa A fixture could not ask — that fixture wrote
# a backlog shape sdd-phase-opener never produces, and the gate was dead against the real one for months.
gate_probe() {
  local hooks="$1" repo="$2" ref="$3" id="$4" ckpt="$5" wt out
  wt="$(mktemp -d)"; rm -rf "$wt"
  git clone -q --no-local --shared --branch "$ref" "$repo" "$wt" 2>/dev/null || { rm -rf "$wt"; echo error; return; }
  write_cursor "$wt/docs/PROGRESS.md" 1 "$id" none none ${ckpt:+"$ckpt"}
  out="$(printf '{"agent_type":"sdd-issue-worker","cwd":"%s","last_assistant_message":"Outcome: green — landed done."}' "$wt" \
          | CLAUDE_PROJECT_DIR="$wt" bash "$hooks/sdd-verify-subagent.sh" 2>/dev/null || true)"
  rm -rf "$wt"
  case "$out" in *'"block"'*) echo block ;; *) echo allow ;; esac
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
