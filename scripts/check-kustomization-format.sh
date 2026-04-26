#!/bin/bash
# Validate kustomization.yaml files follow formatting standards:
# - Resources, components, and bases are alphabetically sorted (pure ASCII/C locale)
# - Blank lines exist between major sections
# - Exception: anythingllm-image can be at the end of components list

set -e

# Use C locale for pure ASCII string comparison to match yq sort behavior
export LC_COLLATE=C

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Checking kustomization.yaml formatting standards..."
echo

violations_found=0
files_checked=0

# Function to check if array is sorted
is_sorted() {
  local -n arr=$1
  local len=${#arr[@]}

  for ((i=0; i<len-1; i++)); do
    if [[ "${arr[i]}" > "${arr[i+1]}" ]]; then
      return 1  # Not sorted
    fi
  done

  return 0  # Sorted
}

# Function to check blank lines
check_blank_lines() {
  local file="$1"
  local violations=()

  # Check for blank line after "kind: Kustomization"
  if grep -q "^kind: Kustomization$" "$file"; then
    # Get line number of "kind: Kustomization"
    local kind_line=$(grep -n "^kind: Kustomization$" "$file" | cut -d: -f1)
    local next_line=$((kind_line + 1))

    # Check if next line is blank
    local next_line_content=$(sed -n "${next_line}p" "$file")
    if [[ -n "$next_line_content" ]]; then
      violations+=("Missing blank line after 'kind: Kustomization' (line $kind_line)")
    fi
  fi

  # Check for blank lines before major sections
  local sections="^(resources|components|bases|patches|replacements|configMapGenerator|secretGenerator|commonAnnotations|commonLabels|namespace|images|replicas):"

  while IFS= read -r line_info; do
    local line_num=$(echo "$line_info" | cut -d: -f1)
    local section_name=$(echo "$line_info" | cut -d: -f2)

    # Skip if this is line 1-3 (likely in header)
    if [[ $line_num -le 3 ]]; then
      continue
    fi

    # Check if previous line is blank
    local prev_line=$((line_num - 1))
    local prev_line_content=$(sed -n "${prev_line}p" "$file")

    if [[ -n "$prev_line_content" && ! "$prev_line_content" =~ ^[[:space:]]*$ ]]; then
      violations+=("Missing blank line before section '$section_name' (line $line_num)")
    fi
  done < <(grep -n -E "$sections" "$file" || true)

  echo "${violations[@]}"
}

# Function to check sorting of a list
check_list_sorting() {
  local file="$1"
  local list_name="$2"
  local allow_exception="${3:-false}"  # For anythingllm-image exception

  # Get the list using yq
  local list_json=$(yq -o json ".$list_name // []" "$file" 2>/dev/null)

  # If list is null or empty, skip
  if [[ "$list_json" == "null" || "$list_json" == "[]" ]]; then
    return 0
  fi

  # Convert to bash array
  local -a items=()
  while IFS= read -r item; do
    items+=("$item")
  done < <(echo "$list_json" | jq -r '.[]' 2>/dev/null)

  # If empty or single item, it's sorted
  if [[ ${#items[@]} -le 1 ]]; then
    return 0
  fi

  # Special case: components list with anythingllm-image exception
  if [[ "$list_name" == "components" && "$allow_exception" == "true" ]]; then
    local last_item="${items[-1]}"
    if [[ "$last_item" == *"anythingllm-image"* ]]; then
      # Remove last item and check if rest is sorted
      local -a items_without_last=("${items[@]:0:${#items[@]}-1}")

      # Check if anythingllm-image would be out of order if not at end
      local -a all_sorted=("${items[@]}")
      IFS=$'\n' all_sorted=($(sort <<<"${all_sorted[*]}"))
      unset IFS

      # If sorted version puts anythingllm-image not at the end, this is the exception
      if [[ "${all_sorted[-1]}" != "$last_item" ]]; then
        # Check if the rest (without anythingllm-image) is sorted
        if ! is_sorted items_without_last; then
          echo "not-sorted"
          return 1
        fi
        return 0  # Valid exception
      fi
    fi
  fi

  # Normal sorting check
  if ! is_sorted items; then
    echo "not-sorted"
    return 1
  fi

  return 0
}

# Process all kustomization.yaml files
for file in $(find . -name "kustomization.yaml" -type f | sort); do
  files_checked=$((files_checked + 1))
  file_violations=()

  # Check blank lines
  blank_line_violations=$(check_blank_lines "$file")
  if [[ -n "$blank_line_violations" ]]; then
    IFS=$'\n' read -rd '' -a violations_array <<<"$blank_line_violations" || true
    for violation in "${violations_array[@]}"; do
      if [[ -n "$violation" ]]; then
        file_violations+=("  - $violation")
      fi
    done
  fi

  # Check resources sorting
  if yq -e '.resources' "$file" >/dev/null 2>&1; then
    if ! check_list_sorting "$file" "resources" "false"; then
      file_violations+=("  - Resources list is not alphabetically sorted")
    fi
  fi

  # Check components sorting (with anythingllm-image exception)
  if yq -e '.components' "$file" >/dev/null 2>&1; then
    if ! check_list_sorting "$file" "components" "true"; then
      file_violations+=("  - Components list is not alphabetically sorted (except anythingllm-image at end)")
    fi
  fi

  # Check bases sorting
  if yq -e '.bases' "$file" >/dev/null 2>&1; then
    if ! check_list_sorting "$file" "bases" "false"; then
      file_violations+=("  - Bases list is not alphabetically sorted")
    fi
  fi

  # If violations found for this file, print them
  if [[ ${#file_violations[@]} -gt 0 ]]; then
    echo -e "${RED}✗${NC} $file"
    printf '%s\n' "${file_violations[@]}"
    echo
    violations_found=$((violations_found + 1))
  fi
done

# Print summary
echo "================================"
echo "Summary:"
echo "  Files checked: $files_checked"

if [[ $violations_found -eq 0 ]]; then
  echo -e "  ${GREEN}✓ All files pass formatting standards${NC}"
  echo "================================"
  exit 0
else
  echo -e "  ${RED}✗ Files with violations: $violations_found${NC}"
  echo "================================"
  echo
  echo -e "${YELLOW}💡 To fix formatting issues, run:${NC}"
  echo "   ./scripts/sort-kustomization-resources.sh"
  echo
  exit 1
fi
