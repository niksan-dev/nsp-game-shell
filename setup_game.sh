#!/usr/bin/env bash

set -e

# =========================================================
# UNITY MODULAR GAME SETUP
# =========================================================

ROOT_DIR=$(pwd)

CONFIG_DIR="$ROOT_DIR/config"

GAMES_DIR="$ROOT_DIR/Games"
PACKAGE_CACHE_DIR="$ROOT_DIR/PackageCache"

mkdir -p "$GAMES_DIR"
mkdir -p "$PACKAGE_CACHE_DIR"

# =========================================================
# LOAD CONFIGS
# =========================================================

GAME_CATALOG=$(cat "$CONFIG_DIR/games.conf")
MODULE_CATALOG=$(cat "$CONFIG_DIR/modules.conf")

# =========================================================
# HELPERS
# =========================================================

get_game_field() {

    local game_id=$1
    local field=$2

    echo "$GAME_CATALOG" \
        | awk -F'|' -v id="$game_id" -v fld="$field" \
        '$1==id {print $fld}'
}

get_module_repo() {

    local module=$1

    echo "$MODULE_CATALOG" \
        | awk -F'|' -v mod="$module" \
        '$1==mod {print $3}'
}

module_exists() {

    local module=$1

    echo "$MODULE_CATALOG" \
        | awk -F'|' -v mod="$module" \
        '$1==mod { found=1 } END { exit !found }'
}

# =========================================================
# GENERATE VSCODE WORKSPACE
# =========================================================

generate_workspace() {

    local WORKSPACE_FILE="$ROOT_DIR/${GAME_NAME}.code-workspace"

    echo ""
    echo "Generating VS Code workspace..."

    cat > "$WORKSPACE_FILE" <<EOF
{
    "folders": [
        {
            "name": "nsp-game-shell",
            "path": "."
        },
        {
            "name": "$GAME_REPO_NAME",
            "path": "Games/$GAME_NAME"
        }
EOF

    while IFS='|' read -r MODULE CACHE_FOLDER VERSION
    do
        [ -z "$MODULE" ] && continue

cat >> "$WORKSPACE_FILE" <<EOF
        ,
        {
            "name": "$CACHE_FOLDER",
            "path": "PackageCache/$CACHE_FOLDER"
        }
EOF

    done < "$LOCK_FILE"

cat >> "$WORKSPACE_FILE" <<EOF

    ],

    "settings": {
        "git.autoRepositoryDetection": "all",
        "git.openRepositoryInParentFolders": "always"
    }
}
EOF

    echo ""
    echo "Workspace generated:"
    echo "  $WORKSPACE_FILE"
}

# =========================================================
# USAGE
# =========================================================

usage() {

    echo ""
    echo "Usage:"
    echo ""
    echo "  ./setup_game.sh <GAME_ID> <MODULES>"
    echo ""
    echo "Examples:"
    echo ""
    echo "  ./setup_game.sh 101 ads"
    echo "  ./setup_game.sh 101 ads analytics"
    echo "  ./setup_game.sh 101 ads@1.0.0"
    echo ""

    exit 1
}

# =========================================================
# VALIDATE INPUT
# =========================================================

if [ $# -lt 2 ]; then
    usage
fi

GAME_ID=$1
shift

GAME_REPO_NAME=$(get_game_field "$GAME_ID" 2)
GAME_NAME=$(get_game_field "$GAME_ID" 3)
GAME_REPO=$(get_game_field "$GAME_ID" 4)

if [ -z "$GAME_NAME" ]; then

    echo ""
    echo "ERROR: Invalid GAME_ID: $GAME_ID"

    exit 1
fi

GAME_PATH="$GAMES_DIR/$GAME_NAME"

# =========================================================
# CLONE GAME
# =========================================================

if [ ! -d "$GAME_PATH" ]; then

    echo ""
    echo "================================================="
    echo "Cloning Game: $GAME_NAME"
    echo "================================================="

    git clone "$GAME_REPO" "$GAME_PATH"

else

    echo ""
    echo "Game already exists: $GAME_NAME"
fi

# =========================================================
# UNITY MODULES
# =========================================================

UNITY_MODULES_DIR="$GAME_PATH/Assets/Modules"

mkdir -p "$UNITY_MODULES_DIR"

LOCK_FILE="$GAME_PATH/modules.lock"

touch "$LOCK_FILE"

# =========================================================
# INSTALL MODULES
# =========================================================

for MODULE_ARG in "$@"
do

    # =====================================================
    # PARSE VERSION
    # =====================================================

    if [[ "$MODULE_ARG" == *"@"* ]]; then

        MODULE_NAME="${MODULE_ARG%@*}"
        MODULE_VERSION="${MODULE_ARG#*@}"

    else

        MODULE_NAME="$MODULE_ARG"
        MODULE_VERSION="latest"

    fi

    echo ""
    echo "================================================="
    echo "Installing Module: $MODULE_NAME"
    echo "Requested Version: $MODULE_VERSION"
    echo "================================================="

    # =====================================================
    # VALIDATE MODULE
    # =====================================================

    if ! module_exists "$MODULE_NAME"; then

        echo ""
        echo "ERROR: Unknown module: $MODULE_NAME"

        continue
    fi

    MODULE_REPO=$(get_module_repo "$MODULE_NAME")

    REPO_NAME=$(basename "$MODULE_REPO" .git)

    GLOBAL_MODULE_PATH="$PACKAGE_CACHE_DIR/$REPO_NAME"

    UNITY_MODULE_PATH="$UNITY_MODULES_DIR/$MODULE_NAME"

    # =====================================================
    # CLONE MODULE
    # =====================================================

    if [ ! -d "$GLOBAL_MODULE_PATH" ]; then

        echo ""
        echo "Cloning module repo..."

        git clone "$MODULE_REPO" "$GLOBAL_MODULE_PATH"

    else

        echo ""
        echo "Module already cached"
    fi

    # =====================================================
    # FETCH LATEST TAGS
    # =====================================================

    cd "$GLOBAL_MODULE_PATH"

    git fetch --tags

    # =====================================================
    # CHECKOUT VERSION
    # =====================================================

    if [ "$MODULE_VERSION" == "latest" ]; then

        LATEST_TAG=$(git tag --sort=-v:refname | head -n 1)

        if [ -z "$LATEST_TAG" ]; then

            echo ""
            echo "WARNING: No tags found"
            echo "Using current branch"

            RESOLVED_VERSION="dev"

        else

            git checkout "$LATEST_TAG"

            RESOLVED_VERSION=${LATEST_TAG#v}
        fi

    else

        git checkout "v$MODULE_VERSION"

        RESOLVED_VERSION="$MODULE_VERSION"
    fi

    cd "$ROOT_DIR"

    # =====================================================
    # CREATE SYMLINK
    # =====================================================

    if [ -L "$UNITY_MODULE_PATH" ]; then

        rm "$UNITY_MODULE_PATH"
    fi

    if [ ! -e "$UNITY_MODULE_PATH" ]; then

        echo ""
        echo "Creating module link..."

        if command -v ln >/dev/null 2>&1; then

            ln -s "$GLOBAL_MODULE_PATH" "$UNITY_MODULE_PATH"

        else

            cmd //c mklink /D \
                "$(cygpath -w "$UNITY_MODULE_PATH")" \
                "$(cygpath -w "$GLOBAL_MODULE_PATH")"
        fi
    fi

    # =====================================================
    # GENERATE ASMDEF
    # =====================================================

    ASMDEF_PATH="$GLOBAL_MODULE_PATH/$MODULE_NAME.asmdef"

    if [ ! -f "$ASMDEF_PATH" ]; then

cat > "$ASMDEF_PATH" <<EOF
{
    "name": "$MODULE_NAME",
    "references": [],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": false
}
EOF

    fi

    # =====================================================
    # UPDATE LOCK FILE
    # =====================================================

    sed -i "/^$MODULE_NAME|/d" "$LOCK_FILE" 2>/dev/null || true

    echo "$MODULE_NAME|$REPO_NAME|$RESOLVED_VERSION" >> "$LOCK_FILE"

done

# =========================================================
# GENERATE WORKSPACE
# =========================================================

generate_workspace

# =========================================================
# SUMMARY
# =========================================================

echo ""
echo "================================================="
echo "SETUP COMPLETE"
echo "================================================="
echo ""

echo "Game:"
echo "  $GAME_NAME"
echo ""

echo "Installed Modules:"
cat "$LOCK_FILE"

echo ""

echo "Open Workspace:"
echo "  ${GAME_NAME}.code-workspace"

echo ""