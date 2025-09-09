#!/bin/bash
set -e

DUMP_DIR="dump"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

restore_from_txt() {
    local dump_file="$1"
    local current_filepath=""

    echo "Starting text-based restore from: '$dump_file'..."

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "--- START: "* ]]; then
            path=${line#--- START: }
            path=${path% ---}
            current_filepath="$path"
            dir=$(dirname "$current_filepath")
            mkdir -p "$dir"
            > "$current_filepath" 
            echo " -> Creating: $current_filepath"
        elif [[ "$line" == "--- END: "* ]]; then
            current_filepath=""
        elif [ -n "$current_filepath" ]; then
            echo "$line" >> "$current_filepath"
        fi
    done < "$dump_file"
}

restore_from_json() {
    local dump_file="$1"

    echo "Starting JSON-based restore from: '$dump_file'..."

    mapfile -t filepaths < <(jq -r 'keys_unsorted[]' "$dump_file")

    for path in "${filepaths[@]}"; do
        echo " -> Creating: $path"
        
        dir=$(dirname "$path")
        mkdir -p "$dir"

        jq -r --arg p "$path" '.[$p]' "$dump_file" | printf '%s' "$(cat)" > "$path"
    done
}

if [ ! -d "$DUMP_DIR" ]; then
    echo -e "${YELLOW}Error: Directory '$DUMP_DIR' not found. Nothing to restore.${NC}"
    exit 1
fi

DUMP_FILES=()
while IFS= read -r -d '' file; do
    DUMP_FILES+=("$file")
done < <(find "$DUMP_DIR" -maxdepth 1 \( -name "*.txt" -o -name "*.json" \) -type f -print0 2>/dev/null | sort -z)

if [ ${#DUMP_FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}Error: No dump files found in '$DUMP_DIR'.${NC}"
    exit 1
fi

echo "Available dump files:"
for i in "${!DUMP_FILES[@]}"; do
    filename=$(basename "${DUMP_FILES[$i]}")
    echo -e "  $((i+1)). ${CYAN}$filename${NC}"
done
echo "  $((${#DUMP_FILES[@]}+1)). Exit"

echo ""
read -p "Select a dump file (1-$((${#DUMP_FILES[@]}+1))) [default: 1]: " selection

selection=${selection:-1}

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $((${#DUMP_FILES[@]}+1)) ]; then
    echo -e "${YELLOW}Error: Invalid selection.${NC}"
    exit 1
fi

if [[ "$selection" == "$((${#DUMP_FILES[@]}+1))" ]]; then
    echo "Operation cancelled."
    exit 0
fi

SELECTED_DUMP_FILE="${DUMP_FILES[$((selection-1))]}"

echo ""
echo -e "Selected file: ${CYAN}'$(basename "$SELECTED_DUMP_FILE")'${NC}"
echo -e "${YELLOW}WARNING: This will OVERWRITE existing files in the current directory.${NC}"
read -p "Are you sure you want to continue? (Y/n): " confirmation

if [[ "$confirmation" == "n" || "$confirmation" == "N" ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""

if [[ "$SELECTED_DUMP_FILE" == *.json ]]; then
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Error: 'jq' is required to process JSON files.${NC}"
        echo "Please install 'jq' (e.g., 'sudo apt-get install jq' or 'brew install jq')."
        exit 1
    fi
    restore_from_json "$SELECTED_DUMP_FILE"
elif [[ "$SELECTED_DUMP_FILE" == *.txt ]]; then
    restore_from_txt "$SELECTED_DUMP_FILE"
else
    echo -e "${YELLOW}Error: Unsupported file type: '$(basename "$SELECTED_DUMP_FILE")'${NC}"
    exit 1
fi

echo -e "${GREEN}Restore process completed.${NC}"