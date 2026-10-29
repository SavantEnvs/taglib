#!/usr/bin/env bash
#
# mayhem/test.sh — RUNS taglib's CppUnit suites plus known-answer probes (all built by mayhem/build.sh;
# nothing is compiled here). Asserts behavior: parsed CppUnit pass counts and exact tag/audio fields
# read from fixed fixtures by the dynamically linked tagreader. A neutered binary prints nothing -> FAIL.
# Emits a CTRF report; exit 0 iff failed==0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


B="$SRC/build/test"
passed=0 ; failed=0

# 1) taglib's own CppUnit suites. Parse the runner's summary: a neutered/missing runner prints no summary
#    and counts as a failure (never a skip).
run_suite() {
  local bin="$1" out n run bad
  if [ ! -x "$bin" ]; then echo "missing test binary $bin (build.sh bug)" >&2; failed=$((failed + 1)); return; fi
  out=$("$bin" 2>&1) || true
  if n=$(printf '%s\n' "$out" | sed -n 's/^OK (\([0-9][0-9]*\))$/\1/p' | head -n1) && [ -n "$n" ]; then
    passed=$((passed + n))
  elif printf '%s\n' "$out" | grep -qE '^Run: +[0-9]+ +Failures: +[0-9]+ +Errors: +[0-9]+'; then
    run=$(printf '%s\n' "$out" | sed -n 's/^Run: *\([0-9]*\).*/\1/p' | head -n1)
    bad=$(printf '%s\n' "$out" | sed -n 's/.*Failures: *\([0-9]*\) *Errors: *\([0-9]*\).*/\1 \2/p' | head -n1 | awk '{print $1+$2}')
    failed=$((failed + bad)) ; passed=$((passed + run - bad))
    printf '%s\n' "$out" | grep -E 'assertion|error|Failure' | head -20 >&2
  else
    echo "$bin produced no CppUnit summary" >&2 ; failed=$((failed + 1))
  fi
}
run_suite "$B/tests/test_runner"
run_suite "$B/tests/test_threadsafety"

# 2) Known-answer probes through the dynamically linked tagreader: fixed fixture -> exact parsed field.
kat() {  # kat <fixture> <exact output line>
  local out
  out=$("$B/examples/tagreader" "$SRC/tests/data/$1" 2>/dev/null) || true
  if printf '%s\n' "$out" | grep -qxF -- "$2"; then
    passed=$((passed + 1))
  else
    echo "KAT FAILED: $1 should print: $2" >&2 ; failed=$((failed + 1))
  fi
}
kat itunes10.mp3 'title   - "iTunes10MP3"'
kat itunes10.mp3 'ALBUMARTIST      - "Album Artist"'
kat itunes10.mp3 'TRACKNUMBER      - "1/10"'
kat itunes10.mp3 'bitrate     - 288'
kat has-tags.m4a 'ARTIST   - "Test Artist"'
kat has-tags.m4a '  mimeType    - "image/jpeg"'
kat xing.mp3 'sample rate - 44100'
kat xing.mp3 'length      - 0:02'
kat sinewave.flac 'bitrate     - 145'
kat lowercase-fields.ogg 'title   - "TEST TITLE"'

emit_ctrf "cppunit+kat" "$passed" "$failed" 0
