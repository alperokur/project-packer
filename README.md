# Project Packer Scripts

A collection of shell scripts designed to bundle project files into a single, self-extracting executable. Ideal for sharing code, creating backups, or providing a complete context to Large Language Models (LLMs).

## Key Features

-   **Two Packing Modes**: Pack an entire project respecting `.gitignore` rules, or pack a specific list of files.
-   **Self-Contained Executable**: The main output is a single `.sh` file that contains all your project files, compressed and encoded. It can be run anywhere to restore the project.
-   **Multiple Formats**: In addition to the self-extracting script, it generates a human-readable `.txt` file and a machine-readable `.json` file for different use cases.
-   **Dependency-Aware**: The scripts check for required tools (`jq`, `git`, etc.) before running.
-   **Manual Restore**: Includes a utility script to restore a project from the `.txt` or `.json` outputs if needed.

## Prerequisites

These scripts require a Unix-like environment (Linux, macOS, WSL) and the following command-line tools:

-   `git` (used by `pack.sh` for ignore rule logic)
-   `jq` (for JSON processing)
-   `base64` (for encoding file content)
-   `xz` (for compressing the payload)

You can install them on Debian/Ubuntu with:
```bash
sudo apt-get update && sudo apt-get install git jq xz-utils
```
Or on macOS with Homebrew:
```bash
brew install git jq xz
```

## Usage / Workflow

### 1. Setup

First, place the `scripts` directory into the root of the project you wish to pack and make the scripts executable.

```bash
# Navigate to your project's root directory
cd /path/to/your/project

# Grant execute permissions
chmod +x scripts/*.sh
```

### 2. Choose a Packing Method

You have two options for packing your project.

#### Option A: Pack the Entire Project (`pack.sh`)

This script bundles your entire project, but intelligently excludes files listed in `.gitignore` and a custom `.packignore` file. This is the most common use case.

1.  **(Optional)** Create a file named `.packignore` in your project root. Add any additional file or directory patterns you want to exclude, using the same syntax as `.gitignore`.
2.  Run the script:

    ```bash
    ./scripts/pack.sh
    ```

#### Option B: Pack a Specific List of Files (`selective.sh`)

This script bundles only the files and directories that you explicitly list in a `.packlist` file. This is useful for creating a minimal package.

1.  Create a file named `.packlist` in your project root.
2.  Add the file paths or glob patterns for the files you want to include, one per line. Comments (`#` or `//`) are ignored.

    *Example `.packlist` file:*
    ```
    # Include all markdown files in the project
    **/*.md

    # Include all source files from the src directory
    src/**/*.js
    src/**/*.css

    # Include a specific configuration file
    config/production.json
    ```
3.  Run the script:

    ```bash
    ./scripts/selective.sh
    ```

### 3. The Output

After running either script, a `dump/` directory will be created. Inside, you will find timestamped files, for example:

-   `dump/2025-09-09_054906.sh`: **The self-extracting script. This is the main file to share.**
-   `dump/2025-09-09_054906.json`: A JSON object mapping file paths to their content.
-   `dump/2025-09-09_054906.txt`: A single text file with all file contents concatenated.

### 4. Unpacking the Project

Give the generated `.sh` file (e.g., `dump/2025-09-09_054906.sh`) to the recipient. They can restore the project by simply running it in their terminal.

```bash
# This will unpack the contents into a new directory named after the original project.
bash 2025-09-09_054906.sh

# Or, they can specify a custom name for the target directory.
bash 2025-09-09_054906.sh my-restored-project
```