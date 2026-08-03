#!/bin/sh

set -eu

product_info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
state_directory="${PANEDROP_BUILD_NUMBER_DIR:-${HOME}/Library/Application Support/DavidLabWorks/PaneDropBuild}"
counter_file="${state_directory}/BuildNumber.txt"

if [ ! -f "${product_info_plist}" ]; then
    echo "error: Built Info.plist not found at ${product_info_plist}"
    exit 1
fi

baseline_number="${CURRENT_PROJECT_VERSION}"
case "${baseline_number}" in
    *[!0-9]*|'')
        echo "error: CURRENT_PROJECT_VERSION must be an integer"
        exit 1
        ;;
esac

build_number="${baseline_number}"
if [ -f "${counter_file}" ]; then
    stored_number="$(tr -d '[:space:]' < "${counter_file}")"
    case "${stored_number}" in
        *[!0-9]*|'')
            echo "error: Invalid local build counter in ${counter_file}"
            exit 1
            ;;
    esac

    if [ "${stored_number}" -gt "${build_number}" ]; then
        build_number="${stored_number}"
    fi
fi

if [ "${ACTION:-}" = "install" ] && [ "${CONFIGURATION:-}" = "Release" ]; then
    mkdir -p "${state_directory}"

    lock_directory="${counter_file}.lock"
    if ! mkdir "${lock_directory}" 2>/dev/null; then
        echo "error: Another archive is updating the build number"
        exit 1
    fi
    temporary_counter="${counter_file}.tmp.$$"
    trap 'rm -f "${temporary_counter}"; rmdir "${lock_directory}" 2>/dev/null || true' EXIT

    build_number=$((build_number + 1))
    printf '%s\n' "${build_number}" > "${temporary_counter}"
    mv "${temporary_counter}" "${counter_file}"
    rmdir "${lock_directory}"
    trap - EXIT
fi

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion ${build_number}" \
    "${product_info_plist}"

echo "PaneDrop build number: ${build_number} (${ACTION:-build}, ${CONFIGURATION:-unknown})"
