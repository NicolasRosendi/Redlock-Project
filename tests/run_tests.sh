#!/usr/bin/env bash
# Ejecuta las pruebas headless. Uso: GODOT=/ruta/a/godot tests/run_tests.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo "== Física de patadas y portero =="
"$GODOT" --headless --path . --fixed-fps 60 res://tests/unit_test.tscn 2>&1 | grep -E "^(OK|FAIL)|PORTERO|FAILURES|SCRIPT ERROR"
echo "== Controles (mando simulado) =="
"$GODOT" --headless --path . --fixed-fps 60 res://tests/input_test.tscn 2>&1 | grep -E "^(OK|FAIL)|FAILURES|SCRIPT ERROR"
echo "== Partidos IA vs IA =="
for size in 3 5 7 11; do
	"$GODOT" --headless --path . --fixed-fps 60 res://tests/sim_test.tscn -- --size=$size --minutes=3 2>&1 | grep -E "RESULT|STATS|SCRIPT ERROR"
done
