#!/bin/bash
set -e

DUMP_DIR="dump"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TXT_OUTPUT_FILE="${DUMP_DIR}/${TIMESTAMP}.txt"
JSON_OUTPUT_FILE="${DUMP_DIR}/${TIMESTAMP}.json"
UNPACK_SCRIPT_FILE="${DUMP_DIR}/${TIMESTAMP}.sh"
CONFIG_IGNORE_FILE=".packignore"
PROJECT_NAME=$(basename "$PWD")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

for cmd in jq base64 xz git; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}WARNING: '$cmd' is required for this script.${NC}"
        echo "Please install '$cmd' (e.g., 'sudo apt-get install $cmd' or 'brew install $cmd')."
        exit 1
    fi
done

echo -e "${CYAN}Starting project packer... (Project Name: ${GREEN}${PROJECT_NAME}${CYAN})${NC}"

TEMP_IGNORE_FILE=$(mktemp)
TEMP_STANDARD_RULES=$(mktemp)
TEMP_MANUAL_IGNORES=$(mktemp)
TEMP_GIT_IGNORES=$(mktemp)
GIT_DIR_WAS_CREATED=false

cleanup() {
    rm -f -- "$TEMP_IGNORE_FILE" "$TEMP_STANDARD_RULES" "$TEMP_MANUAL_IGNORES" "$TEMP_GIT_IGNORES"
    if [ "$GIT_DIR_WAS_CREATED" = true ]; then
        rm -rf .git
        echo -e "${CYAN}Temporary .git repository removed.${NC}"
    fi
}
trap cleanup EXIT

mkdir -p "$DUMP_DIR"

echo "### PROJECT CONTENT DUMP - $(date) ###" > "$TXT_OUTPUT_FILE"
echo "" >> "$TXT_OUTPUT_FILE"
json_data_for_ai="{}"
json_data_for_unpacker="{}"

if [ -f ".gitignore" ]; then cat ".gitignore" >> "$TEMP_IGNORE_FILE"; fi
if [ -f "$CONFIG_IGNORE_FILE" ]; then
    if [ -s "$TEMP_IGNORE_FILE" ]; then echo "" >> "$TEMP_IGNORE_FILE"; fi
    cat "$CONFIG_IGNORE_FILE" >> "$TEMP_IGNORE_FILE"
fi

if [ -s "$TEMP_IGNORE_FILE" ]; then
    echo -e "\n${CYAN}--- Combined ignore rules being applied ---${NC}"
    sed 's/^/  /' "$TEMP_IGNORE_FILE"
    echo -e "${CYAN}-------------------------------------------${NC}\n"
fi

echo -e "${CYAN}Finding and filtering files...${NC}"

base_file_list=$(find . -name ".git" -type d -prune -o -path "./${DUMP_DIR}" -prune -o -type f -print | sed 's|^\./||')

if [ ! -s "$TEMP_IGNORE_FILE" ]; then
    all_files="$base_file_list"
else
    echo -e "${CYAN}Applying custom '/' rule logic...${NC}"
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        pattern=$(echo "$pattern" | xargs)
        if [[ "$pattern" == \#* ]] || [ -z "$pattern" ]; then continue; fi

        if [[ "$pattern" == */ ]]; then
            base_pattern=${pattern%/}
            if [ -f "$base_pattern" ]; then
                echo "$base_pattern" >> "$TEMP_MANUAL_IGNORES"
            elif [ -d "$base_pattern" ]; then
                find "$base_pattern" -type f 2>/dev/null | sed 's|^\./||' >> "$TEMP_MANUAL_IGNORES"
            fi
        else
            echo "$pattern" >> "$TEMP_STANDARD_RULES"
        fi
    done < "$TEMP_IGNORE_FILE"

    echo -e "${CYAN}Applying standard rules with git...${NC}"
    if [ ! -d ".git" ]; then
        git init -q
        GIT_DIR_WAS_CREATED=true
    fi

    if [ -s "$TEMP_STANDARD_RULES" ]; then
        echo "$base_file_list" | git -c core.excludesFile="$TEMP_STANDARD_RULES" check-ignore --no-index --stdin >> "$TEMP_GIT_IGNORES"
    fi

    all_ignored_files=$(cat "$TEMP_MANUAL_IGNORES" "$TEMP_GIT_IGNORES" | sort -u)
    
    all_files=$(echo "$base_file_list" | grep -v -x -F -f <(echo "$all_ignored_files") || true)
fi


file_list=$(echo "$all_files" | sed '/^$/d')
processed_count=0
empty_count=0

if [ -z "$file_list" ]; then
    echo -e "${YELLOW}No files to process after applying filters.${NC}"
else
    while IFS= read -r file; do
        if [ ! -f "$file" ]; then continue; fi
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