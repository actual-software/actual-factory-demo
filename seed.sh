#!/usr/bin/env bash
# seed.sh
# ----------------------------------------------------------------------------
# Fills the task queue with the ASCII-art work the factory will chew through.
#
# What this opens by default:
#   - 2 epic beads (Letters a–m, Letters n–z)
#   - 26 letter tasks (a.md ... z.md, split across the two epics)
#
# ADR 0001 also allows numbers 1–100. Those epics are written below but left
# commented out, because 126 tasks is a lot of queue to look at when you only
# intend to run two or three of them. Uncomment them if you want the full set.
#
# Each child task is parented to its epic (--parent <epic-id>) and stamped
# with metadata.target_file = "ascii/<filename>" so agents can locate the file
# they own without parsing their own task title.
#
# Run this from the rig root, after `gc rig add` has initialized its beads
# database and before you hand any work to an agent:
#   ./seed.sh
#
# Every bead here is created with `gc bd`, not bare `bd`. This matters: bare
# `bd create` honours the `routing.contributor` setting, so on a machine that
# has one configured it writes the beads into that personal store instead of
# the rig's. `gc sling` and the supervisor only ever read the rig's store, so
# the beads would seed "successfully" and then be invisible to the factory --
# `gc sling` fails with `bead "<id>" not found in store rig:<rig>`. The trap is
# that bare `bd list`/`bd show` read *both* stores, so the queue still looks
# correctly seeded. `gc bd` writes where the agents actually read.
# ----------------------------------------------------------------------------

set -euo pipefail

# --- preflight ---------------------------------------------------------------

# Require gc, bd and jq (jq plucks the epic id from --json output). `gc bd` is
# a passthrough that runs `bd` in the resolved rig directory, so both binaries
# need to be present.
for tool in gc bd jq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: '${tool}' not found on PATH. Install it and re-run." >&2
    exit 1
  fi
done

# Idempotency guard: if the first epic title already exists, bail out.
# Coarse on purpose — we refuse to double-seed rather than dedupe per-bead.
#
# `bd search` always echoes the search term in its "No issues found
# matching '<term>'" message, so plain `grep -q` would false-positive
# on every empty db. Use --json + jq length instead.
if [ "$(gc bd search "Letters a–m" --json 2>/dev/null | jq 'length')" -gt 0 ]; then
  echo "Looks like 'Letters a–m' already exists in this beads db." >&2
  echo "Seed appears to have run. Aborting to avoid duplicates." >&2
  echo "To reseed, delete the existing beads first, e.g.:" >&2
  echo "  gc bd list --json | jq -r '.[].id' | xargs -n1 gc bd delete --force" >&2
  exit 1
fi

# --- helpers -----------------------------------------------------------------

# create_epic <title> <epic-slug>
# Creates one epic bead, returns its bead id on stdout.
create_epic() {
  local title="$1"
  local slug="$2"
  gc bd create \
    --type=epic \
    --priority=2 \
    --metadata "{\"epic\":\"${slug}\"}" \
    --json \
    "${title}" \
  | jq -r .id
}

# create_child <epic-id> <filename>  (e.g. create_child bd-12 a.md)
# Creates one child task bead under the given epic, stamped with target_file.
create_child() {
  local parent="$1"
  local fname="$2"
  gc bd create \
    --type=task \
    --parent="${parent}" \
    --priority=2 \
    --metadata "{\"target_file\":\"ascii/${fname}\"}" \
    --silent \
    "Implement ${fname}" \
  >/dev/null
}

# seed_letter_epic <title> <slug> <start-letter> <end-letter>
seed_letter_epic() {
  local title="$1" slug="$2" start="$3" end="$4"
  echo "==> creating epic: ${title}"
  local epic_id; epic_id="$(create_epic "${title}" "${slug}")"
  echo "    epic id: ${epic_id}"
  local count=0
  # shellcheck disable=SC2046  # brace expansion is fine here
  for c in $(eval echo {${start}..${end}}); do
    create_child "${epic_id}" "${c}.md"
    count=$((count + 1))
  done
  echo "    opened ${count} child task(s)"
  TOTAL_TASKS=$((TOTAL_TASKS + count))
  TOTAL_EPICS=$((TOTAL_EPICS + 1))
}

# seed_number_epic <title> <slug> <start-num> <end-num>
seed_number_epic() {
  local title="$1" slug="$2" start="$3" end="$4"
  echo "==> creating epic: ${title}"
  local epic_id; epic_id="$(create_epic "${title}" "${slug}")"
  echo "    epic id: ${epic_id}"
  local count=0
  for n in $(seq "${start}" "${end}"); do
    create_child "${epic_id}" "${n}.md"
    count=$((count + 1))
  done
  echo "    opened ${count} child task(s)"
  TOTAL_TASKS=$((TOTAL_TASKS + count))
  TOTAL_EPICS=$((TOTAL_EPICS + 1))
}

# --- run ---------------------------------------------------------------------

# Counted as epics are created, so commenting a seed_* call in or out below
# keeps the summary honest.
TOTAL_EPICS=0
TOTAL_TASKS=0

# Two letter epics (a–m = 13, n–z = 13).
seed_letter_epic "Letters a–m" "letters-a-m" "a" "m"
seed_letter_epic "Letters n–z" "letters-n-z" "n" "z"

# Ten number epics, ten beads each.
# seed_number_epic "Numbers 1–10"   "numbers-1-10"     1  10
# seed_number_epic "Numbers 11–20"  "numbers-11-20"   11  20
# seed_number_epic "Numbers 21–30"  "numbers-21-30"   21  30
# seed_number_epic "Numbers 31–40"  "numbers-31-40"   31  40
# seed_number_epic "Numbers 41–50"  "numbers-41-50"   41  50
# seed_number_epic "Numbers 51–60"  "numbers-51-60"   51  60
# seed_number_epic "Numbers 61–70"  "numbers-61-70"   61  70
# seed_number_epic "Numbers 71–80"  "numbers-71-80"   71  80
# seed_number_epic "Numbers 81–90"  "numbers-81-90"   81  90
# seed_number_epic "Numbers 91–100" "numbers-91-100"  91 100

# --- summary -----------------------------------------------------------------

echo
echo "Seed complete."
echo "  epics opened: ${TOTAL_EPICS}"
echo "  tasks opened: ${TOTAL_TASKS}"
echo "  total beads:  $((TOTAL_EPICS + TOTAL_TASKS))"
echo
echo "Next steps:"
echo "  gc bd list --type=epic   # see the epics you just opened"
echo "  gc bd ready              # find a task to start on"
echo "  gc sling ascii-art/factory.planner <bead-id> --on ascii-art   # run one"
