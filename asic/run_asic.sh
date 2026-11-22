#!/bin/bash
# Harden cpu_core with LibreLane (OpenLane successor) on SkyWater 130 nm.
#   asic/run_asic.sh                  -> clock period from config.json (ns)
#   asic/run_asic.sh 15               -> 15 ns clock target, run tag "p15"
#   TAG=mytag asic/run_asic.sh 15
#
# Needs: Docker (e.g. Colima) and LibreLane in ~/.venvs/rv32i-asic
#   (python3 -m venv ~/.venvs/rv32i-asic && ~/.venvs/rv32i-asic/bin/pip install librelane==3.0.17)
# Keep the venv out of iCloud-synced folders (Documents/Desktop): offloaded
# files make every start wait on downloads.
#
# The flow runs in a staging copy outside the repo (~/.cache/rv32i-asic/<tag>).
# The repo may live in an iCloud-synced folder, where macOS can offload
# files ("dataless"); the container's file sharing can't read those.
# Copying on the host forces them back. Key results are copied into
# asic/results/<tag>/.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIBRELANE="${LIBRELANE:-$HOME/.venvs/rv32i-asic/bin/librelane}"
PERIOD="$1"
TAG="${TAG:-${PERIOD:+p$PERIOD}}"
TAG="${TAG:-default}"
STAGE="$HOME/.cache/rv32i-asic/$TAG"    # one staging dir per run, so runs can go in parallel

mkdir -p "$STAGE/rtl" "$STAGE/asic"
cp "$REPO"/rtl/*.v "$STAGE/rtl/"
cp "$REPO/asic/config.json" "$STAGE/asic/"

OVERRIDE=()
[ -n "$PERIOD" ] && OVERRIDE=(-c "CLOCK_PERIOD=$PERIOD")

cd "$STAGE"
echo "Running LibreLane (tag $TAG) in $STAGE ..."
"$LIBRELANE" --docker-no-tty --dockerized --run-tag "$TAG" --overwrite \
    asic/config.json "${OVERRIDE[@]}" > "$STAGE/flow_$TAG.log" 2>&1 < /dev/null \
    || { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$STAGE/flow_$TAG.log" | grep -a -B2 -A8 "ERROR" | tail -30; exit 1; }

RUN="$STAGE/asic/runs/$TAG"
OUT="$REPO/asic/results/$TAG"
mkdir -p "$OUT"
cp "$RUN/final/metrics.json" "$RUN/final/metrics.csv" "$OUT/" 2>/dev/null || true
cp "$STAGE/flow_$TAG.log" "$OUT/flow.log"
echo "Done. Run directory: $RUN"
echo "Metrics copied to:   $OUT"
