#!/bin/bash
set -e

SPEC_FILE=".packlist"
OUTPUT_DIR="dump"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TXT_OUTPUT_FILE="${OUTPUT_DIR}/selective_${TIMESTAMP}.txt"
JSON_OUTPUT_FILE="${OUTPUT_DIR}/selective_${TIMESTAMP}.json"
UNPACK_SCRIPT_FILE="${OUTPUT_DIR}/selective_${TIMESTAMP}.sh"
PROJECT_NAME=$(basename "$PWD")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

for cmd in jq base64 xz; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}WARNING: '$cmd' is required for this script.${NC}"
        echo "Please install '$cmd' (e.g., 'sudo apt-get install $cmd' or 'brew install $cmd')."
        exit 1
    fi
done

echo -e "${CYAN}Starting selective project packer... (Project Name: ${GREEN}${PROJECT_NAME}${CYAN})${NC}"

if [ ! -f "$SPEC_FILE" ]; then
    echo -e "${YELLOW}ERROR: Specification file '${SPEC_FILE}' not found.${NC}"
    echo "Please create this file and list the files/directories you want to pack, one per line."
    exit 1
fi

echo -e "${CYAN}Reading and expanding patterns from: ${GREEN}${SPEC_FILE}${NC}"

temp_file_list=""
while IFS= read -r pattern || [ -n "$pattern" ]; do
    pattern=$(echo "$pattern" | xargs)
    if [[ "$pattern" == \#* ]] || [[ "$pattern" == //* ]] || [ -z "$pattern" ]; then
        continue
    fi

    if [[ "$pattern" == */ ]]; then
        local_dir=${pattern%/}
        if [ -d "$local_dir" ]; then
            echo " -> Expanding directory: $pattern"
            found_files=$(find "$local_dir" -type f | sed 's|^\./||')
            if [ -n "$found_files" ]; then
                temp_file_list+="${found_files}"$'\n'
            fi
        else
            echo -e " -> ${YELLOW}Warning: Directory '$local_dir' not found, skipping.${NC}"
        fi
    else
        echo " -> Expanding pattern: $pattern"
        shopt -s globstar nullglob
        for file in $pattern; do
            if [ -f "$file" ]; then
                temp_file_list+="$file"$'\n'
            fi
        done
        shopt -u globstar nullglob
    fi
done < "$SPEC_FILE"

file_list=$(echo -e "$temp_file_list" | sed '/^\s*$/d' | sort -u)

mkdir -p "$OUTPUT_DIR"

echo "### SELECTIVE PROJECT CONTENT DUMP - $(date) ###" > "$TXT_OUTPUT_FILE"
echo "" >> "$TXT_OUTPUT_FILE"
json_data_for_ai="{}"
json_data_for_unpacker="{}"

processed_count=0
empty_count=0

if [ -z "$file_list" ]; then
    echo -e "${YELLOW}No files found matching the patterns in '${SPEC_FILE}'.${NC}"
else
    while IFS= read -r file; do
        if [ ! -f "$file" ]; then
            continue
        fi

        if [ ! -s "$file" ]; then
            echo " -> Skipping (Empty): $file"
            empty_count=$((empty_count + 1))
            continue
        fi

        echo " -> Processing: $file"

        echo "--- START: $file ---" >> "$TXT_OUTPUT_FILE"
        cat "$file" >> "$TXT_OUTPUT_FILE"
        if [ "$(tail -c1 "$file")" ]; then echo "" >> "$TXT_OUTPUT_FILE"; fi
        echo "--- END: $file ---" >> "$TXT_OUTPUT_FILE"
        echo "" >> "$TXT_OUTPUT_FILE"

        json_data_for_ai=$(echo "$json_data_for_ai" | jq --arg path "$file" --rawfile content "$file" '. + {($path): $content}')
        b64_content=$(base64 -w 0 < "$file")
        json_data_for_unpacker=$(echo "$json_data_for_unpacker" | jq --arg path "$file" --arg content "$b64_content" '. + {($path): $content}')

        processed_count=$((processed_count + 1))
    done <<< "$file_list"
fi

if [ "$processed_count" -eq 0 ] && [ "$empty_count" -eq 0 ]; then
    echo -e "${YELLOW}No files were found to pack. Exiting.${NC}"
    exit 0
fi

echo "$json_data_for_ai" | jq '.' > "$JSON_OUTPUT_FILE"

echo -e "${CYAN}Creating compressed, self-contained unpack script...${NC}"
cat << EOF > "$UNPACK_SCRIPT_FILE"
#!/bin/bash
set -e
GREEN='\\033[0;32m'; CYAN='\\033[0;36m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
DEFAULT_TARGET_DIR='${PROJECT_NAME}'
if [[ "\$1" == "-h" || "\$1" == "--help" ]]; then
    echo "Usage: \$0 [TARGET_DIRECTORY]"; echo "  Unpacks project to TARGET_DIRECTORY (default: '\$DEFAULT_TARGET_DIR')."; exit 0
fi
TARGET_DIR="\${1:-\$DEFAULT_TARGET_DIR}"
for cmd in jq base64 xz; do
    if ! command -v \$cmd &> /dev/null; then echo -e "\${YELLOW}ERROR: '\$cmd' is required.${NC}" >&2; exit 1; fi
done
echo -e "\${CYAN}Unpacking to: \${GREEN}\$TARGET_DIR\${NC}"; mkdir -p -- "\$TARGET_DIR"
file_count=0
while IFS= read -r entry; do
    filepath=\$(echo "\$entry" | jq -r '.key'); b64_content=\$(echo "\$entry" | jq -r '.value')
    full_target_path="\$TARGET_DIR/\$filepath"; echo "  -> Creating: \$full_target_path"
    dirpath=\$(dirname -- "\$filepath"); if [[ "\$dirpath" != "." ]]; then mkdir -p -- "\$TARGET_DIR/\$dirpath"; fi
    echo "\$b64_content" | base64 --decode > "\$full_target_path"; file_count=\$((file_count + 1))
done < <(sed '1,/^PAYLOAD:\$/d' "\$0" | xz -d | jq -c '. | to_entries[]')
echo ""; echo -e "\${GREEN}Unpacking complete! \${NC}Created \${GREEN}\$file_count\${NC} files in \${CYAN}'\$TARGET_DIR'\${NC}."
exit 0
PAYLOAD:
EOF

echo "$json_data_for_unpacker" | xz -9 -c >> "$UNPACK_SCRIPT_FILE"
chmod +x "$UNPACK_SCRIPT_FILE"

echo ""
echo -e "${GREEN}Packing complete!${NC}"
echo "----------------------------------------"
echo -e "Total ${GREEN}$processed_count${NC} files processed."
if [ $empty_count -gt 0 ]; then echo -e "Total ${CYAN}$empty_count${NC} empty files skipped."; fi
echo "----------------------------------------"
echo -e "JSON output (for AI):            ${CYAN}'$JSON_OUTPUT_FILE'${NC}"
echo -e "Self-contained unpacker (to run): ${CYAN}'$UNPACK_SCRIPT_FILE'${NC}"
echo -e "Text output (for context):       ${CYAN}'$TXT_OUTPUT_FILE'${NC}"
echo "----------------------------------------"