#!/usr/bin/env bash
# Deep validation script for nvidia-sdk
# Tests binary execution, library linking, and functionality

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASS_COUNT++))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  ((FAIL_COUNT++))
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARN_COUNT++))
}

log_info() {
  echo -e "  $1"
}

# Check if a binary exists and is executable
check_binary() {
  local path=$1
  local name=$2

  if [[ -f $path ]]; then
    if [[ -x $path ]]; then
      log_pass "Binary exists and is executable: $name"
      return 0
    else
      log_fail "Binary exists but not executable: $name"
      return 1
    fi
  else
    log_fail "Binary not found: $name at $path"
    return 1
  fi
}

# Check library dependencies with ldd
check_ldd() {
  local binary=$1
  local name=$2

  if ! ldd "$binary" &>/dev/null; then
    log_fail "ldd failed for $name (not a dynamic executable?)"
    return 1
  fi

  local missing=$(ldd "$binary" 2>&1 | grep "not found" || true)
  if [[ -n $missing ]]; then
    log_fail "Missing libraries for $name:"
    echo "$missing" | sed 's/^/    /'
    return 1
  else
    log_pass "All libraries found for $name"
    return 0
  fi
}

# Check RPATH/RUNPATH
check_rpath() {
  local binary=$1
  local name=$2

  if command -v patchelf &>/dev/null; then
    local rpath=$(patchelf --print-rpath "$binary" 2>/dev/null || echo "")
    local interpreter=$(patchelf --print-interpreter "$binary" 2>/dev/null || echo "")

    if [[ -n $rpath ]]; then
      log_info "RPATH: $rpath"
    fi
    if [[ -n $interpreter ]]; then
      log_info "Interpreter: $interpreter"
    fi
  fi
}

# Try to execute a binary with --help or --version
test_execution() {
  local binary=$1
  local name=$2
  local args=${3:---help}

  if timeout 5s "$binary" $args &>/dev/null; then
    log_pass "Execution test passed: $name $args"
    return 0
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log_warn "Execution timeout: $name $args"
    else
      log_warn "Execution failed (exit $exit_code): $name $args"
    fi
    return 1
  fi
}

# Check shared library symbols
check_library_symbols() {
  local lib=$1
  local name=$2
  local expected_symbols=("${@:3}")

  if [[ ! -f $lib ]]; then
    log_fail "Library not found: $name at $lib"
    return 1
  fi

  local missing_symbols=()
  for sym in "${expected_symbols[@]}"; do
    if ! nm -D "$lib" 2>/dev/null | grep -q "$sym"; then
      missing_symbols+=("$sym")
    fi
  done

  if [[ ${#missing_symbols[@]} -eq 0 ]]; then
    log_pass "All expected symbols found in $name"
    return 0
  else
    log_fail "Missing symbols in $name:"
    printf '    %s\n' "${missing_symbols[@]}"
    return 1
  fi
}

# Print summary
print_summary() {
  echo -e "\n${BLUE}=== Validation Summary ===${NC}"
  echo -e "Passed: ${GREEN}${PASS_COUNT}${NC}"
  echo -e "Failed: ${RED}${FAIL_COUNT}${NC}"
  echo -e "Warnings: ${YELLOW}${WARN_COUNT}${NC}"

  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "\n${GREEN}All critical checks passed!${NC}"
    return 0
  else
    echo -e "\n${RED}Some checks failed. Review output above.${NC}"
    return 1
  fi
}

export -f log_section log_pass log_fail log_warn log_info
export -f check_binary check_ldd check_rpath test_execution check_library_symbols
export PASS_COUNT FAIL_COUNT WARN_COUNT

# Main validation will be called from nix with specific package paths
"$@"
