#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
LOG=${1:-logs}
mkdir -p "$LOG" build
fails=0
total=0

files_of() {
    grep -v '^#' "$1" | tr -d '\r' | grep -v '^ *$' | tr '\n' ' '
}

if command -v verilator >/dev/null 2>&1; then
    verilator --lint-only -Wall -Wno-fatal -Irtl/include --top-module l1d_prefetch_unit \
        $(files_of filelists/rtl.f) > "$LOG/lint_unit.log" 2>&1
    rc=$?
    grep -c '%Warning' "$LOG/lint_unit.log" | sed 's/^/lint warnings: /'
    if [ $rc -ne 0 ] || grep -q '%Error' "$LOG/lint_unit.log"; then
        echo "FAIL lint (see $LOG/lint_unit.log)"
        grep '%Error' "$LOG/lint_unit.log" | head -20
        fails=$((fails+1))
    else
        echo "PASS lint"
    fi
    total=$((total+1))
fi

while read -r name tb flist args; do
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    total=$((total+1))
    echo "RUN $name $(date +%T)"
    out="build/$name.vvp"
    if ! iverilog -g2005 -DL1D_DEBUG -Irtl/include -Iref -o "$out" "tb/$tb.v" \
            $(files_of "filelists/$flist.f") > "$LOG/$name.compile.log" 2>&1; then
        echo "FAIL $name (compile, see $LOG/$name.compile.log)"
        head -20 "$LOG/$name.compile.log"
        fails=$((fails+1))
        continue
    fi
    timeout 1200 vvp -n "$out" $args > "$LOG/$name.log" 2>&1
    [ $? -eq 124 ] && echo "ERROR: run time-out (1200 s)" >> "$LOG/$name.log"
    if grep -q "TEST PASSED" "$LOG/$name.log" && ! grep -q "ERROR" "$LOG/$name.log"; then
        echo "PASS $name | $(grep SUMMARY "$LOG/$name.log")"
    else
        echo "FAIL $name | $(grep SUMMARY "$LOG/$name.log")"
        grep "ERROR" "$LOG/$name.log" | head -20
        fails=$((fails+1))
    fi
done < <(grep -v '^#' scripts/tests.txt | tr -d '\r')

echo "RESULT: $((total-fails)) of $total passed"
[ $fails -eq 0 ]
