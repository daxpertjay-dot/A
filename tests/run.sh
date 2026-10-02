#!/usr/bin/env bash
# Runs the headless test suite (needs lune + python3). Usage:
#   tests/run.sh            all tests
#   tests/run.sh boost sim  just these
# Each test prints a line ending in "OK" when it passes; full logs go to
# tests/.mirror/<name>.log.
set -u
cd "$(dirname "$0")/.."
python3 tests/mirror.py || exit 1
names=("$@")
[ ${#names[@]} -eq 0 ] && names=(track server ui boost sim)
failed=0
for name in "${names[@]}"; do
	log="tests/.mirror/$name.log"
	start=$(date +%s)
	timeout 300 lune run "tests/$name.luau" >"$log" 2>&1
	code=$?
	secs=$(( $(date +%s) - start ))
	if [ $code -eq 0 ] && grep -qE "(SMOKE|SERVER|UI|BOOST|SIM) OK" "$log"; then
		echo "PASS  $name (${secs}s)"
	else
		echo "FAIL  $name (exit $code, ${secs}s) — see $log"
		tail -15 "$log" | sed 's/^/      /'
		failed=1
	fi
done
exit $failed
