#!/usr/bin/env bash
# =============================================================================
# Roda o testbench tb_PoseidonSequentialShared no Verilator 5.x
#
# Uso:
#   ./run_verilator.sh                  # procura fontes em . (recursivo)
#   ./run_verilator.sh -d rtl           # procura fontes em ./rtl
#   ./run_verilator.sh -d rtl -t tb_PoseidonSequentialShared
#   ./run_verilator.sh -f lista.f       # usa sua propria lista de arquivos
#   ./run_verilator.sh --trace          # liga o VCD (mais lento)
#   ./run_verilator.sh --seed 123       # semente dos $urandom
#   ./run_verilator.sh --rand           # randomiza o estado inicial (pode disparar
#                                       # asserts antes do reset terminar)
#   ./run_verilator.sh --dry            # so mostra o comando, nao executa
# =============================================================================
set -eo pipefail   # sem -u: bash 4.2 (clusters antigos) trata array vazio como erro

SRC_DIR="."
TOP="PoseidonTester"
FILELIST=""
TRACE=0
DRY=0
RAND=0
SEED=1
OSS_CAD="${OSS_CAD:-$HOME/oss-cad-suite}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)   SRC_DIR="$2"; shift 2 ;;
    -t|--top)   TOP="$2"; shift 2 ;;
    -f)         FILELIST="$2"; shift 2 ;;
    --trace)    TRACE=1; shift ;;
    --seed)     SEED="$2"; shift 2 ;;
    --rand)     RAND=1; shift ;;
    --dry)      DRY=1; shift ;;
    -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "opcao desconhecida: $1"; exit 1 ;;
  esac
done

# ---------- ambiente: OSS CAD Suite, se o verilator nao estiver no PATH ----------
if ! command -v verilator >/dev/null 2>&1; then
  if [[ -f "$OSS_CAD/environment" ]]; then
    # shellcheck disable=SC1091
    source "$OSS_CAD/environment"
  fi
fi
if ! command -v verilator >/dev/null 2>&1; then
  echo "ERRO: verilator nao encontrado."
  echo "  - extraia o OSS CAD Suite em ~/oss-cad-suite  (ou: export OSS_CAD=/caminho)"
  echo "  - ou rode:  module load apps/verilator/<versao>"
  exit 1
fi

VER=$(verilator --version | awk '{print $2}')
MAJOR=${VER%%.*}
echo ">> Verilator $VER"
if [[ "$MAJOR" -lt 5 ]]; then
  echo "ERRO: precisa de Verilator 5.x (--binary --timing). Versao atual: $VER"
  exit 1
fi

# ---------- monta a lista de arquivos ----------
ARGS_FILES=()
if [[ -n "$FILELIST" ]]; then
  ARGS_FILES=(-f "$FILELIST")
else
  mapfile -t ALL < <(find "$SRC_DIR" -type f \( -name '*.sv' -o -name '*.v' \) \
      -not -path '*/obj_dir/*' | sort)

  TB_FILE=""
  PKGS=(); REST=()
  for f in "${ALL[@]}"; do
    base=$(basename "$f"); base=${base%.*}
    if [[ "$base" == "$TOP" ]]; then TB_FILE="$f"; continue; fi
    # ignora outros testbenches
    if [[ "$base" == tb_* || "$base" == *_tb || "$base" == *_tb_* ]]; then continue; fi
    if grep -qE '^\s*package\s+' "$f"; then PKGS+=("$f"); else REST+=("$f"); fi
  done

  if [[ -z "$TB_FILE" ]]; then
    echo "ERRO: nao achei $TOP.sv dentro de '$SRC_DIR'."
    echo "      use -d <pasta> ou -t <nome_do_modulo_top>."
    exit 1
  fi
  ARGS_FILES=("${PKGS[@]}" "${REST[@]}" "$TB_FILE")

  echo ">> ${#PKGS[@]} package(s), ${#REST[@]} arquivo(s) de design, 1 testbench ($TB_FILE)"
fi

# diretorios de include (.svh / .vh)
INC=()
while IFS= read -r d; do INC+=("-I$d"); done < <(
  find "$SRC_DIR" -type f \( -name '*.svh' -o -name '*.vh' -o -name '*.sv' -o -name '*.v' \) \
    -not -path '*/obj_dir/*' -printf '%h\n' 2>/dev/null | sort -u)

# ---------- flags ----------
FLAGS=(
  --binary --timing -j 0
  -Wno-fatal -Wno-lint -Wno-style
  --public-flat-rw
  --x-initial unique --x-assign unique
  --top-module "$TOP"
  --Mdir obj_dir
)
[[ "$TRACE" -eq 1 ]] && FLAGS+=(--trace)

CMD=(verilator "${FLAGS[@]}" "${INC[@]}" "${ARGS_FILES[@]}")
echo ">> ${CMD[*]}"
[[ "$DRY" -eq 1 ]] && exit 0

# ---------- compila ----------
rm -rf obj_dir
"${CMD[@]}" 2>&1 | tee build.log

# ---------- roda ----------
RUNARGS=(+verilator+seed+"$SEED")
[[ "$RAND" -eq 1 ]] && RUNARGS+=(+verilator+rand+reset+2)
echo ">> rodando: ${RUNARGS[*]}"
set +e
"./obj_dir/V$TOP" "${RUNARGS[@]}" 2>&1 | tee sim.log
RC=${PIPESTATUS[0]}
set -e

echo
echo ">> logs: build.log, sim.log   (exit code da simulacao: $RC)"
grep -E "RESULTADO|checks OK|FAIL" sim.log || true
exit "$RC"