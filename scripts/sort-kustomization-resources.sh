#!/bin/bash
# Sort resources, components, and bases lists in all kustomization.yaml files alphabetically

set -e

echo "Sorting kustomization.yaml files alphabetically..."
echo

sorted_count=0
total_count=0

# Function to add blank lines before major sections
add_section_spacing() {
  local file="$1"
  local tmpfile="${file}.tmp"

  awk '
    BEGIN { prev_blank = 0; in_header = 0; seen_kind = 0 }

    # Track apiVersion and kind (header section)
    /^apiVersion:/ { in_header = 1; print; next }
    /^kind:/ { seen_kind = 1; print; next }

    # Major section keywords - add blank line before them if not already present
    /^(resources|components|bases|patches|replacements|configMapGenerator|secretGenerator|commonAnnotations|commonLabels|namespace|images|replicas|namePrefix|nameSuffix|vars|patchesStrategicMerge|patchesJson6902):/ {
      # Add blank line before section if previous line was not blank
      if (!prev_blank) {
        print ""
      }
      prev_blank = 0
      print
      next
    }

    # Track blank lines
    /^[[:space:]]*$/ { prev_blank = 1; print; next }

    # Any other line
    { prev_blank = 0; print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
}

sortable_fields=(resources components bases)

for file in $(find . -name "kustomization.yaml" -type f); do
  total_count=$((total_count + 1))

  file_modified=false
  for field in "${sortable_fields[@]}"; do
    if yq -e ".$field" "$file" >/dev/null 2>&1; then
      if [ "$file_modified" = false ]; then
        echo "Processing: $file"
        file_modified=true
      fi
      yq -i ".$field |= sort" "$file"
      echo "  ✅ Sorted .$field"
    fi
  done

  if [ "$file_modified" = true ]; then
    add_section_spacing "$file"
    echo "  ✅ Added section spacing"
    sorted_count=$((sorted_count + 1))
    echo
  fi
done

echo "================================"
echo "Summary:"
echo "  Total kustomization.yaml files: $total_count"
echo "  Files sorted: $sorted_count"
echo "  Files skipped (no sortable lists): $((total_count - sorted_count))"
echo "================================"
echo
echo "✅ Done! Run 'git diff' to see changes."
