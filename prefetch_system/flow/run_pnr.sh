#!/usr/bin/env bash
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
TOP=${TOP:-pf3_timing_top}
PERIOD=${PERIOD:-240}
SYNTH_PERIOD=${SYNTH_PERIOD:-200}
CORNER=${CORNER:-BC}
UTIL=${UTIL:-40}
OUT=${OUT:-$ROOT/pnr_out/${TOP}_${CORNER}_p${PERIOD}}
mkdir -p "$OUT/inputs" "$OUT/keep"
OUT=$(cd "$OUT" && pwd)
if [[ -z ${FLOW_HOME:-} ]]; then
    for p in /OpenROAD-flow-scripts/flow /opt/OpenROAD-flow-scripts/flow; do
        [[ -f $p/Makefile ]] && { export FLOW_HOME=$p; break; }
    done
fi
[[ -f ${FLOW_HOME:-}/Makefile ]] || { echo "no ORFS flow dir"; exit 1; }

FILES=""
while read -r f; do
    [[ -z "$f" || "$f" == \#* || "$f" == -* ]] && continue
    FILES="$FILES $ROOT/$f"
done < "$ROOT/filelists/pnr.f"

SDC="$OUT/inputs/$TOP.sdc"
cat > "$SDC" <<EOF
set_units -time ps -capacitance fF
create_clock -name clk -period $PERIOD [get_ports clk]
set_clock_uncertainty [expr {0.05 * $PERIOD}] [get_clocks clk]
set in_ports [lsearch -all -inline -not -exact [all_inputs] [get_ports clk]]
set_input_delay 0 -clock clk \$in_ports
set_output_delay 0 -clock clk [all_outputs]
set_false_path -from \$in_ports
set_false_path -to [all_outputs]
EOF

CONFIG="$OUT/inputs/$TOP.mk"
cat > "$CONFIG" <<EOF
export PLATFORM               = asap7
export CORNER                 = $CORNER
export DESIGN_NAME            = $TOP
export VERILOG_FILES          = $FILES
export VERILOG_INCLUDE_DIRS   = $ROOT/rtl/include
export SDC_FILE               = $SDC
export CORE_UTILIZATION       = $UTIL
export PLACE_DENSITY_LB_ADDON = 0.20
export SYNTH_HIERARCHICAL     = 0
export ABC_CLOCK_PERIOD_IN_PS = $SYNTH_PERIOD
export TNS_END_PERCENT        = 100
export NUM_CORES              = 2
EOF

W="$OUT/work"
mkdir -p "$W"
{
    echo "top=$TOP period=$PERIOD synth_period=$SYNTH_PERIOD corner=$CORNER util=$UTIL"
    openroad -version 2>&1 | head -1
    (cd "$FLOW_HOME" && git log -1 --format='ORFS %H' 2>/dev/null)
} | tee "$OUT/keep/versions.txt"

echo "=== synthesis ==="
(cd "$FLOW_HOME" && make DESIGN_CONFIG="$CONFIG" WORK_HOME="$W" synth) > "$OUT/keep/synth.log" 2>&1
SYN_RC=$?
echo "synthesis exit code $SYN_RC"
PNR_RC=na
if [[ $SYN_RC -eq 0 ]]; then
    echo "=== place and route ==="
    (cd "$FLOW_HOME" && make DESIGN_CONFIG="$CONFIG" WORK_HOME="$W") > "$OUT/keep/pnr.log" 2>&1
    PNR_RC=$?
    echo "place and route exit code $PNR_RC"
    tail -40 "$OUT/keep/pnr.log"
    echo "=== extra timing reports ==="
    (cd "$FLOW_HOME" && make DESIGN_CONFIG="$CONFIG" WORK_HOME="$W" \
        RUN_SCRIPT="$HERE/paths.tcl" run) > "$OUT/keep/paths.log" 2>&1 || true
else
    tail -40 "$OUT/keep/synth.log"
fi

for d in logs reports; do
    mkdir -p "$OUT/keep/$d"
    cp -r "$W/$d/asap7/$TOP/base/." "$OUT/keep/$d/" 2>/dev/null || true
done
python3 "$HERE/summarize.py" one --work "$W" --top "$TOP" --period "$PERIOD" --corner "$CORNER" \
    --synth-rc "$SYN_RC" --pnr-rc "$PNR_RC" --out "$OUT/keep/summary.json" || true
find "$W" -name '*.rpt' -path '*reports*' -newer "$CONFIG" -exec cp -t "$OUT/keep" {} + 2>/dev/null || true
exit 0
