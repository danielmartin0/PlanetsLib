#!/bin/bash

# SPDX-License-Identifier: LGPL-3.0-or-later WITH FUnit-CI-Exception
#
# Special exception to LGPL-3.0: Project-specific tweaks and adaptations
# to CI configuration files (changes made to make the file work for a
# different project) may be used, copied, modified, and distributed
# without triggering LGPL copyleft on the downstream project. This does
# not apply to general improvements that would benefit the original project.

ANY_FAILURE=0

mkdir -p /factorio/saves

if [ -s "save_names.txt" ]; then
    for fn in $(cat save_names.txt); do
        echo "____SCENARIO____: $fn"
        EXIT_CODE=0

        cp /*.zip "$MODS"/
        export SAVE_NAME="/saves/$fn"
        /opt/factorio/bin/x64/factorio \
            --sync-mods "$SAVE_NAME" \
            --mod-directory "$MODS" \
            --server-settings "$CONFIG/server-settings.json" || EXIT_CODE=$?
        if [ "$EXIT_CODE" -ne 0 ]; then
            ANY_FAILURE=$EXIT_CODE
        fi

        /opt/factorio/bin/x64/factorio \
            --test-save "$SAVE_NAME" \
            --mod-directory "$MODS" \
            --instrument-mod "funit" \
            --server-settings "$CONFIG/server-settings.json" || EXIT_CODE=$?
        if [ "$EXIT_CODE" -ne 0 ]; then
            ANY_FAILURE=$EXIT_CODE
        fi
        sleep 1
    done
fi

if [ -s "scenario_names.txt" ]; then
    cp /*.zip "$MODS"/
    # update-mods.sh already skips the Space Age DLC mods, but recycler is
    # also built into the game and must not be downloaded from the portal.
    UPDATE_IGNORE="recycler"
    for zipfile in "$MODS"/*.zip; do
        [ -f "$zipfile" ] || continue
        next_mod=$(basename "$zipfile" .zip)
        next_mod="${next_mod%_*}"
        case "$next_mod" in
            ("base"|"recycler"|"quality"|"elevated-rails"|"space-age") continue ;;
        esac
        case ",${UPDATE_IGNORE}," in
            (*",${next_mod},"*) continue ;;
        esac
        UPDATE_IGNORE="${UPDATE_IGNORE:+$UPDATE_IGNORE,}${next_mod}"
    done
    export UPDATE_IGNORE
    for fn in $(cat scenario_names.txt); do
        EXIT_CODE=0
        echo "____SCENARIO____: $fn"

        if [ -s "/factorio/scenarios/$fn/mod-list.json" ]; then
            echo "Using $fn/mod-list.json"
            cp "/factorio/scenarios/$fn/mod-list.json" "$MODS"/
        else
            echo "Using default mod-list.json"
            cp "/mod-list.json" "$MODS"/
        fi
        if [ -s "factorio/scenarios/$fn/mod-settings.dat" ]; then
            echo "Using $fn/mod-settings.dat"
            cp "factorio/scenarios/$fn/mod-settings.dat" "$MODS"/
        else
            echo "Using default mod settings"
            rm -f "$MODS/mod-settings.dat"
        fi

        /docker-update-mods.sh
        /opt/factorio/bin/x64/factorio \
            --test-scenario "$fn" \
            --mod-directory "$MODS" \
            --instrument-mod "funit" \
            --server-settings "$CONFIG/server-settings.json" || EXIT_CODE=$?
        if [ "$EXIT_CODE" -ne 0 ]; then
            ANY_FAILURE=$EXIT_CODE
        fi
        sleep 1
    done
fi

if [ ! -s "scenario_names.txt" ] && [ ! -s "save_names.txt" ]; then
    EXIT_CODE=0
    export UPDATE_IGNORE="${MOD_NAME}"
    echo "____SCENARIO____: freeplay"
    echo "Using default mod-list.json"
    cp /*.zip "$MODS"/
    cp "/mod-list.json" "$MODS"/ 2>/dev/null || true
    /docker-update-mods.sh
    /opt/factorio/bin/x64/factorio \
        --test-scenario "base/freeplay" \
        --test-ticks 600 \
        --mod-directory "$MODS" \
        --instrument-mod "funit" \
        --server-settings "$CONFIG/server-settings.json" || EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ]; then
        ANY_FAILURE=$EXIT_CODE
    fi
fi

exit $ANY_FAILURE
