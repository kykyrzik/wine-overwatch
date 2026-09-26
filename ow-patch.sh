#!/bin/bash
# Applies the Overwatch fixes to the Wine engine inside a Sikarugir wrapper.
# Usage: ./ow-patch.sh status|apply|revert /path/to/Wrapper.app
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SUFFIX=".ow-orig"

die() { echo "error: $*" >&2; exit 1; }

usage() {
    echo "usage: $0 status|apply|revert /path/to/Wrapper.app" >&2
    exit 2
}

[ $# -eq 2 ] || usage
ACTION="$1"
APP="${2%/}"
LIB="$APP/Contents/SharedSupport/wine/lib/wine/x86_64-unix"
[ -d "$LIB" ] || die "no Wine engine at $LIB — is this a Sikarugir wrapper?"

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
bytes_at() { xxd -p -s "$(($2))" -l "$3" "$1" | tr -d '\n'; }

# The pristine hash of a file: of its backup if we patched it, otherwise of the file itself.
pristine_sha() {
    local f="$LIB/$1"
    if [ -f "$f$BACKUP_SUFFIX" ]; then sha "$f$BACKUP_SUFFIX"; else sha "$f"; fi
}

# A build matches when every file is either pristine (by hash) or already carries all of that build's patches.
find_build() {
    local dir name want ok
    for dir in "$HERE"/builds/*/; do
        BUILD="${dir%/}"
        ok=1
        while IFS=$'\t' read -r name want; do
            case "$name" in ''|'#'*) continue ;; esac
            [ -f "$LIB/$name" ] || { ok=0; break; }
            [ "$(pristine_sha "$name")" = "$want" ] && continue
            [ "$(file_state "$name")" = patched ] || { ok=0; break; }
        done < "$dir/originals.tsv"
        if [ $ok -eq 1 ]; then echo "$BUILD"; return 0; fi
    done
    return 1
}

patch_lines() { grep -v -e '^#' -e '^$' "$BUILD/patches.tsv"; }

# Prints "original", "patched" or "mixed" for one file.
file_state() {
    local name="$1" f="$LIB/$1" id file off orig new n cur
    local n_orig=0 n_new=0 n_all=0
    while IFS=$'\t' read -r id file off orig new; do
        [ "$file" = "$name" ] || continue
        n=$(( ${#orig} / 2 ))
        cur=$(bytes_at "$f" "$off" "$n")
        n_all=$((n_all + 1))
        [ "$cur" = "$orig" ] && n_orig=$((n_orig + 1))
        [ "$cur" = "$new" ] && n_new=$((n_new + 1))
    done < <(patch_lines)
    if [ $n_new -eq $n_all ]; then echo patched
    elif [ $n_orig -eq $n_all ]; then echo original
    else echo mixed
    fi
}

files() { patch_lines | cut -f2 | sort -u; }

wrapper_running() {
    pgrep -f "$APP/Contents" >/dev/null 2>&1
}

do_status() {
    local name
    echo "engine build: $(basename "$BUILD")"
    for name in $(files); do
        printf '  %-12s %s' "$name" "$(file_state "$name")"
        [ -f "$LIB/$name$BACKUP_SUFFIX" ] && printf '  (backup: %s%s)' "$name" "$BACKUP_SUFFIX"
        echo
    done
}

patch_file() {
    local name="$1" f="$LIB/$1" tmp id file off orig new n cur
    case "$(file_state "$name")" in
        patched) echo "  $name: already patched"; return 0 ;;
        mixed) die "$name is partially patched or modified by something else; run revert first" ;;
    esac
    [ -f "$f$BACKUP_SUFFIX" ] || cp -p "$f" "$f$BACKUP_SUFFIX"
    tmp="$(mktemp "$f.XXXXXX")"
    cp -p "$f" "$tmp"
    while IFS=$'\t' read -r id file off orig new; do
        [ "$file" = "$name" ] || continue
        n=$(( ${#orig} / 2 ))
        cur=$(bytes_at "$tmp" "$off" "$n")
        [ "$cur" = "$orig" ] || { rm -f "$tmp"; die "$name@$off: expected $orig, found $cur"; }
        printf '%s' "$new" | xxd -r -p | dd of="$tmp" bs=1 seek="$((off))" conv=notrunc 2>/dev/null
    done < <(patch_lines)
    codesign -f -s - "$tmp" 2>/dev/null || { rm -f "$tmp"; die "codesign failed for $name"; }
    mv "$tmp" "$f"
    [ "$(file_state "$name")" = patched ] || die "$name: verification after patching failed"
    echo "  $name: patched"
}

revert_file() {
    local name="$1" f="$LIB/$1"
    if [ ! -f "$f$BACKUP_SUFFIX" ]; then echo "  $name: no $BACKUP_SUFFIX backup, nothing to revert"; return 0; fi
    cp -p "$f$BACKUP_SUFFIX" "$f"
    rm -f "$f$BACKUP_SUFFIX"
    echo "  $name: restored"
}

BUILD="$(find_build)" || die "unsupported engine build: the original ntdll.so/winemac.so hashes match nothing in builds/.
See docs/porting.md to port the patches to this build."

case "$ACTION" in
    status) do_status ;;
    apply)
        wrapper_running && die "the wrapper is running; quit the game, Battle.net and the wrapper first"
        echo "engine build: $(basename "$BUILD")"
        for name in $(files); do patch_file "$name"; done
        ;;
    revert)
        wrapper_running && die "the wrapper is running; quit the game, Battle.net and the wrapper first"
        for name in $(files); do revert_file "$name"; done
        ;;
    *) usage ;;
esac
