#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

#===================================================
#Constants
#===================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT_DIR="$SCRIPT_DIR"

CONFIG_DIR="$ROOT_DIR/config"

GAME_DIR="$ROOT_DIR/Games"

MODULE_DIR="$ROOT_DIR/Modules"

WORKSPACE_DIR="$ROOT_DIR/Workspaces"

CURRENT_GAME_FILE="$ROOT_DIR/.current_game"

#CURRENT_MODULE_FILE="$ROOT_DIR/.current_modules"

GAME_CONFIG="$CONFIG_DIR/games.conf"

MODULE_CONFIG="$CONFIG_DIR/modules.conf"

#===================================================
#Logger
#===================================================

log_info() {

    printf "\033[1;32m[INFO]\033[0m %s\n" "$*"

}

log_warn() {

    printf "\033[1;33m[WARN]\033[0m %s\n" "$*"

}

log_error() {

    printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2

}

die() {

    log_error "$*"

    exit 1

}

#===================================================
#Validation
#===================================================
require_file() {

    [[ -f "$1" ]] || die "Missing file: $1"

}

require_directory() {

    [[ -d "$1" ]] || die "Missing directory: $1"

}

#===================================================
# Generic helper.
#===================================================
find_record() {

    local file="$1"

    local key="$2"

    grep -E "^${key}\|" "$file" || true

}

get_game_record() {

    find_record "$GAME_CONFIG" "$1"

}

get_module_record() {

    find_record "$MODULE_CONFIG" "$1"

}

field() {

    local record="$1"

    local index="$2"

    echo "$record" | cut -d'|' -f"$index"

}

git_clone() {

    local repo="$1"

    local branch="$2"

    local folder="$3"

    git clone \
        --branch "$branch" \
        "$repo" \
        "$folder"

}

git_update() {

    local folder="$1"

    git -C "$folder" pull

}

git_branch() {

    git -C "$1" rev-parse --abbrev-ref HEAD

}

prepare_workspace() {

    mkdir -p "$GAME_DIR"

    mkdir -p "$MODULE_DIR"

    mkdir -p "$WORKSPACE_DIR"

}

save_current_game() {

cat > "$CURRENT_GAME_FILE" <<EOF
GAME_ID=$1
GAME_FOLDER=$2
GAME_NAME=$3
GAME_BRANCH=$4
GAME_PATH=$5
EOF

}

load_current_game() {

    [[ -f "$CURRENT_GAME_FILE" ]] || return

    source "$CURRENT_GAME_FILE"

}

get_module_list_file() {

    load_current_game

    [[ -z "${GAME_PATH:-}" ]] && die "No active game."

    echo "$GAME_PATH/.modules"

}

module_installed() {

    local module="$1"

    local module_file

    module_file=$(get_module_list_file)

    [[ -f "$module_file" ]] || touch "$module_file"

    grep -Fxq "$module" "$module_file"

}

install_module() {

    local module="$1"

    module_installed "$module" && return

    local record
    record=$(get_module_record "$module")

    [[ -z "$record" ]] && die "Unknown module : $module"

    local folder
    local branch
    local repo
    local dependencies

    folder=$(field "$record" 2)
    branch=$(field "$record" 4)
    repo=$(field "$record" 5)
    dependencies=$(field "$record" 6)

    #
    # Install dependencies first
    #
    if [[ -n "$dependencies" ]]; then

        IFS=',' read -ra deps <<< "$dependencies"

        for dep in "${deps[@]}"
        do
            install_module "$dep"
        done

    fi

    log_info "Installing module : $module"

    if [[ ! -d "$MODULE_DIR/$folder/.git" ]]; then

    git_clone \
        "$repo" \
        "$branch" \
        "$MODULE_DIR/$folder"

    else

        log_info "Module already cloned : $module"

    fi

    local module_file

    module_file=$(get_module_list_file)

    touch "$module_file"

    echo "$module" >> "$module_file"

}
remove_module() {

    local module="$1"

    local module_file

    module_file=$(get_module_list_file)

    module_installed "$module" || die "Module not installed."

    grep -Fxv "$module" "$module_file" > "$module_file.tmp"

    mv "$module_file.tmp" "$module_file"

    log_info "Removed : $module"

    generate_manifest
    generate_workspace

}

update_modules() {

    while read -r module
    do

        [[ -z "$module" ]] && continue

        local record

        record=$(get_module_record "$module")

        [[ -z "$record" ]] && continue

        local folder

        folder=$(field "$record" 2)

        git_update "$MODULE_DIR/$folder"

    local module_file

    module_file=$(get_module_list_file)

    done < "$module_file"

}

list_modules() {

    printf "\n"

    printf "%-25s %-15s\n" "Module" "Status"

    printf "%-25s %-15s\n" \
        "-------------------------" \
        "--------------"

    while IFS='|' read -r module folder package branch repo deps
    do

        [[ -z "$module" ]] && continue
        [[ "$module" =~ ^# ]] && continue

        local status=""

        if module_installed "$module"
        then
            status="<Installed>"
        fi

        printf "%-25s %-15s\n" \
            "$module" \
            "$status"

    done < "$MODULE_CONFIG"

    printf "\n"

}
#===================================================
#Create Game
#==================================================

create_game() {

    local game_id="$1"

    [[ -z "$game_id" ]] && die "Game ID required."

    local record
    record=$(get_game_record "$game_id")

    [[ -z "$record" ]] && die "Unknown game id : $game_id"

    local folder
    local name
    local branch
    local repo

    folder=$(field "$record" 2)
    name=$(field "$record" 3)
    branch=$(field "$record" 4)
    repo=$(field "$record" 5)

    local game_path="$GAME_DIR/$folder"

    log_info "Creating game : $name"

    if [[ -d "$game_path/.git" ]]; then
        log_warn "Game already exists."
    else
        git_clone "$repo" "$branch" "$game_path"
    fi

    save_current_game \
        "$game_id" \
        "$folder" \
        "$name" \
        "$branch" \
        "$game_path"

    touch "$game_path/.modules"

    log_info "Current game : $name"

    generate_manifest
    generate_workspace

}

#===================================================
#Switch Game
#==================================================

switch_game() {

    local game_id="$1"

    [[ -z "$game_id" ]] && die "Game ID required."

    local record
    record=$(get_game_record "$game_id")

    [[ -z "$record" ]] && die "Unknown game id : $game_id"

    local folder
    local name
    local branch

    folder=$(field "$record" 2)
    name=$(field "$record" 3)
    branch=$(field "$record" 4)

    local game_path="$GAME_DIR/$folder"

    [[ -d "$game_path/.git" ]] || die "Game is not created. Run game create first."

    save_current_game \
        "$game_id" \
        "$folder" \
        "$name" \
        "$branch" \
        "$game_path"

    echo "Switched to : $name"

    generate_manifest
    generate_workspace

}

add_module() {

    load_current_game

    [[ -z "${GAME_ID:-}" ]] && \
        die "No active game."

    install_module "$1"

    generate_manifest
    generate_workspace
}

#===================================================
#list games
#==================================================

list_games() {

    load_current_game

    printf "\n"

    printf "%-6s %-25s %-15s\n" "ID" "Game" "Status"

    printf "%-6s %-25s %-15s\n" "------" "-------------------------" "--------------"

    while IFS='|' read -r id folder name branch repo
    do

        [[ -z "$id" ]] && continue
        [[ "$id" =~ ^# ]] && continue

        local status=""

        if [[ "${GAME_ID:-}" == "$id" ]]; then
            status="<Current>"
        fi

        printf "%-6s %-25s %-15s\n" \
            "$id" \
            "$name" \
            "$status"

    done < "$GAME_CONFIG"

    printf "\n"

}

#===================================================
#Generate Manifest
#===================================================


generate_manifest() {

    load_current_game

    [[ -z "${GAME_PATH:-}" ]] && die "No active game."

    local module_file="$GAME_PATH/.modules"

    local manifest="$GAME_PATH/Packages/manifest.json"

    mkdir -p "$GAME_PATH/Packages"

    cat > "$manifest" <<EOF
{
    "dependencies": {
EOF

    local first=true

    while read -r module
    do

        [[ -z "$module" ]] && continue

        local record
        record=$(get_module_record "$module")

        [[ -z "$record" ]] && continue

        local folder
        local package

        folder=$(field "$record" 2)
        package=$(field "$record" 3)

        if [[ "$first" == true ]]; then
            first=false
        else
            echo "," >> "$manifest"
        fi

        printf '        "%s": "file:../../../Modules/%s"' \
            "$package" \
            "$folder" >> "$manifest"

    done < "$module_file"

    cat >> "$manifest" <<EOF

    }
}
EOF

    log_info "Manifest generated."

}


#==================================================
#Generate Workspace
#==================================================

generate_workspace() {

    load_current_game

    [[ -z "${GAME_PATH:-}" ]] && die "No active game."

    mkdir -p "$WORKSPACE_DIR"

    local workspace="$WORKSPACE_DIR/$GAME_NAME.code-workspace"

    cat > "$workspace" <<EOF
{
    "folders": [

        {
            "name": "$GAME_NAME",
            "path": "../Games/$GAME_FOLDER"
        },

        {
            "name": "Modules",
            "path": "../Modules"
        }

    ]
}
EOF

    log_info "Workspace generated."

}


#==================================================
#Doctor
#==================================================

doctor() {

    printf "\n"

    require_file "$GAME_CONFIG"

    require_file "$MODULE_CONFIG"

    load_current_game

    [[ -z "${GAME_ID:-}" ]] && die "No active game."

    [[ -d "$GAME_PATH" ]] || die "Game folder missing."

    [[ -d "$GAME_PATH/Packages" ]] || \
        die "Packages folder missing."

    [[ -f "$GAME_PATH/.modules" ]] || \
        die ".modules missing."

    printf "Everything looks good.\n"

}

#touch "$CURRENT_MODULE_FILE"


case "$1" in

    game)

    SUBCOMMAND="${2:-}"

    case "$SUBCOMMAND" in

        create)

            create_game "${3:-}"

            ;;

        switch)

            switch_game "${3:-}"

            ;;

        list)

            list_games

            ;;

        *)

            usage

            ;;

    esac

    ;;

   module)

    SUBCOMMAND="${2:-}"

    case "$SUBCOMMAND" in

        add)

            add_module "${3:-}"

            ;;

        remove)

            remove_module "${3:-}"

            ;;

        list)

            list_modules

            ;;

        update)

            update_modules

            ;;

        *)

            usage

            ;;

    esac

    ;;

    workspace)
        generate_manifest
        generate_workspace
        ;;

    doctor)
        doctor
        ;;

    *)

        usage

        ;;

esac