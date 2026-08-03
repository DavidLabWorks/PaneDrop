#!/bin/sh

set -eu

product_info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
counter_file="${SRCROOT}/BuildSupport/BuildNumber.txt"

if [ ! -f "${product_info_plist}" ]; then
    echo "error: Built Info.plist not found at ${product_info_plist}"
    exit 1
fi

lock_directory="${counter_file}.lock"
if ! mkdir "${lock_directory}" 2>/dev/null; then
    echo "error: Another build is updating the build number"
    exit 1
fi
temporary_counter="${counter_file}.tmp.$$"
trap 'rm -f "${temporary_counter}"; rmdir "${lock_directory}" 2>/dev/null || true' EXIT

if [ ! -f "${counter_file}" ]; then
    echo "error: Build counter not found at ${counter_file}"
    exit 1
fi

previous_number="$(tr -d '[:space:]' < "${counter_file}")"
case "${previous_number}" in
    *[!0-9]*|'')
        echo "error: Invalid build counter in ${counter_file}"
        exit 1
        ;;
esac

build_number=$((previous_number + 1))
printf '%s\n' "${build_number}" > "${temporary_counter}"
mv "${temporary_counter}" "${counter_file}"
rmdir "${lock_directory}"
trap - EXIT

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion ${build_number}" \
    "${product_info_plist}"

echo "PaneDrop build number: ${build_number}"
