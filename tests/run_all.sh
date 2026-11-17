#!/bin/sh
# Lance tous les tests hors jeu ; usage : sh run_all.sh <python du venv lupa> <dossier tests> <dossier addon>
# Chaque sortie est gardée dans <test>.new ; un test échoue s'il s'arrête sur une erreur Lua.
PY="$1"; T="$2"; A="$3"
fail=0
for t in solver_test classe_test gear_test fusion_test scenario ui_test focus_test noop_test options_test promo_test promo_test17 pin_test propositions_test stab_test extras_test group_test robust_test region_test rythme_test v18_test; do
  if [ "$t" = solver_test ]; then extra="SOLVER_PATH=$A/Solver.lua"; else extra=""; fi
  "$PY" -I "$T/run_lua.py" "$T/$t.lua" TESTS="$T" ADDON_DIR="$A" $extra > "$T/$t.new" 2>&1
  code=$?
  last=$(tail -n 1 "$T/$t.new")
  if [ $code -ne 0 ] || grep -q -e "LuaError" -e "Traceback" "$T/$t.new"; then
    echo "ECHEC $t (code $code) : $last"; fail=1
  else
    echo "ok    $t"
  fi
done
exit $fail
