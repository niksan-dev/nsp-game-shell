#!/usr/bin/env bash

set -e

# =========================================================
# UNITY MODULAR GAME SETUP
# =========================================================

ROOT_DIR=$(pwd)

GAMES_DIR="$ROOT_DIR/Games"
MODULES_DIR="$ROOT_DIR/Modules"

mkdir -p "$GAMES_DIR"
mkdir -p "$MODULES_DIR"

# =========================================================
# GAME CATALOG
# FORMAT:
# GAME_ID|GAME_NAME|REPO_URL
# =========================================================

read -r -d '' GAME_CATALOG <<'EOF' || true
101|GoldenHot|git@gitlab.company.com:games/golden-hot.git
102|SplendidHot|git@gitlab.company.com:games/splendid-hot.git
103|Burning777|git@gitlab.company.com:games/burning777.git
EOF

# =========================================================
# MODULE CATALOG
# FORMAT:
# MODULE_NAME|REPO_URL
# =========================================================

read -r -d '' MODULE_CATALOG <<'EOF' || true
ui|git@gitlab.company.com:modules/game-ui.git
battlepass|git@gitlab.company.com:modules/game-battlepass.git
leaderboard|git@gitlab.company.com:modules/game-leaderboard.git
inventory|git@gitlab.company.com:modules/game-inventory.git
events|git@gitlab.company.com:modules/game-events.git
analytics|git@gitlab.company.com:modules/game-analytics.git
shared|git@gitlab.company.com:modules/game-shared.git
EOF

# =========================================================
# HELPERS
# =========================================================

echo "XXXXXXX"
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
        '$1==mod {print $2}'
}

module_exists() {
    local module=$1

    echo "$MODULE_CATALOG" \
        | awk -F'|' -v mod="$module" \
        '$1==mod { found=1 } END { exit !found }'
}

usage() {
    echo ""
    echo "Usage:"
    echo ""
    echo "Setup:"
    echo "  ./setup_game.sh <GAME_ID> <MODULE_1> <MODULE_2> ..."
    echo ""
    echo "Add module:"
    echo "  ./setup_game.sh <GAME_ID> add <MODULE_1> ..."
    echo ""
    echo "Remove module:"
    echo "  ./setup_game.sh <GAME_ID> remove <MODULE_1> ..."
    echo ""
    echo "Examples:"
    echo ""
    echo "  ./setup_game.sh 101 ui battlepass leaderboard"
    echo "  ./setup_game.sh 101 add inventory"
    echo "  ./setup_game.sh 101 remove leaderboard"
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

GAME_NAME=$(get_game_field "$GAME_ID" 2)
GAME_REPO=$(get_game_field "$GAME_ID" 3)

if [ -z "$GAME_NAME" ]; then
    echo ""
    echo "ERROR: Invalid GAME_ID: $GAME_ID"
    exit 1
fi

GAME_PATH="$GAMES_DIR/$GAME_NAME"

# =========================================================
# DETERMINE ACTION
# =========================================================

ACTION="setup"

if [ "$1" == "add" ] || [ "$1" == "remove" ]; then
    ACTION=$1
    shift
fi

if [ $# -lt 1 ]; then
    echo ""
    echo "ERROR: No modules specified"
    exit 1
fi

MODULE_LIST=("$@")

# =========================================================
# CLONE GAME PROJECT
# =========================================================

if [ ! -d "$GAME_PATH" ]; then

    echo ""
    echo "================================================="
    echo "Cloning Unity Game: $GAME_NAME"
    echo "================================================="

    git clone "$GAME_REPO" "$GAME_PATH"

else
    echo ""
    echo "Game already exists: $GAME_NAME"
fi

# =========================================================
# UNITY MODULE DIRECTORY
# =========================================================

UNITY_MODULES_DIR="$GAME_PATH/Assets/Modules"

mkdir -p "$UNITY_MODULES_DIR"

ACTIVE_MODULES_FILE="$GAME_PATH/active_modules.txt"

touch "$ACTIVE_MODULES_FILE"

# =========================================================
# PROCESS MODULES
# =========================================================

for MODULE in "${MODULE_LIST[@]}"
do

    if ! module_exists "$MODULE"; then
        echo ""
        echo "WARNING: Unknown module: $MODULE"
        continue
    fi

    MODULE_REPO=$(get_module_repo "$MODULE")

    GLOBAL_MODULE_PATH="$MODULES_DIR/$MODULE"

    UNITY_MODULE_PATH="$UNITY_MODULES_DIR/$MODULE"

    # =====================================================
    # REMOVE MODULE
    # =====================================================

    if [ "$ACTION" == "remove" ]; then

        echo ""
        echo "Removing module: $MODULE"

        rm -rf "$UNITY_MODULE_PATH"

        rm -rf "$UNITY_MODULE_PATH.meta"

        sed -i "/^$MODULE$/d" "$ACTIVE_MODULES_FILE"

        continue
    fi

    # =====================================================
    # CLONE GLOBAL MODULE CACHE
    # =====================================================

    if [ ! -d "$GLOBAL_MODULE_PATH" ]; then

        echo ""
        echo "Cloning module repo: $MODULE"

        git clone "$MODULE_REPO" "$GLOBAL_MODULE_PATH"

    else
        echo ""
        echo "Module already cached: $MODULE"
    fi

    # =====================================================
    # COPY MODULE INTO UNITY PROJECT
    # =====================================================

    if [ ! -d "$UNITY_MODULE_PATH" ]; then

        echo ""
        echo "Installing module into Unity project: $MODULE"

        cp -R "$GLOBAL_MODULE_PATH" "$UNITY_MODULE_PATH"

    else
        echo ""
        echo "Module already installed: $MODULE"
    fi

    # =====================================================
    # REGISTER ACTIVE MODULE
    # =====================================================

    if ! grep -qx "$MODULE" "$ACTIVE_MODULES_FILE"; then
        echo "$MODULE" >> "$ACTIVE_MODULES_FILE"
    fi
done

# =========================================================
# GENERATE UNITY ASMDEF FILES
# OPTIONAL
# =========================================================

echo ""
echo "Generating Assembly Definitions..."

while IFS= read -r MODULE
do
    [ -z "$MODULE" ] && continue

    ASMDEF_PATH="$UNITY_MODULES_DIR/$MODULE/$MODULE.asmdef"

    if [ ! -f "$ASMDEF_PATH" ]; then

cat > "$ASMDEF_PATH" <<EOF
{
    "name": "$MODULE",
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

done < "$ACTIVE_MODULES_FILE"

# =========================================================
# SUMMARY
# =========================================================

echo ""
echo "================================================="
echo "UNITY GAME SETUP COMPLETE"
echo "================================================="
echo ""
echo "Game:"
echo "  $GAME_NAME"
echo ""
echo "Unity Project:"
echo "  $GAME_PATH"
echo ""
echo "Installed Modules:"
echo ""

cat "$ACTIVE_MODULES_FILE"

echo ""
echo "Unity Modules Directory:"
echo "  $UNITY_MODULES_DIR"
echo ""
echo "Open this project in Unity Hub."
echo ""