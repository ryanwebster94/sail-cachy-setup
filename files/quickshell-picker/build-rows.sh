#!/bin/bash
# Build cached carousel rows; paths are NUL-delimited until encoded as JSON.
set -euo pipefail

if (( $# != 3 )) || [[ $1 != wallpaper && $1 != folder ]]; then
  echo "usage: build-rows.sh <wallpaper|folder> <directory> <out.json>" >&2
  exit 1
fi
mode="$1"
dir="${2:-$HOME/Pictures}"
out="$3"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/qs-picker"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/qs-picker/folder.current"
mkdir -p "$CACHE/wallpapers" "$CACHE/folders"

if [[ ! -d $dir ]]; then
  printf '{"items":[],"selected":""}\n' > "$out"
  exit 0
fi
dir="$(realpath -- "$dir")"
# Concurrent hotkey presses must not publish half-written cache files.
exec {cache_lock}>"$CACHE/build.lock"
flock "$cache_lock"
rows="$(mktemp "$CACHE/rows.XXXXXX")"
trap 'rm -f -- "$rows" "$rows.json" "$rows.sig"' EXIT

image_filter=( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' )
media_filter=( "${image_filter[@]}" -o -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' )
hash() { sha256sum | cut -d' ' -f1; }
dkey="$(printf '%s' "$dir" | hash)"
rowjson="$CACHE/rows-$mode.$dkey.json"
sigfile="$CACHE/rows-$mode.$dkey.sig"

if [[ $mode == wallpaper ]]; then
  sig="$(find -L "$dir" -maxdepth 1 -type f \( "${media_filter[@]}" \) -printf '%p %T@ %C@ %s\0' | sort -z | hash)"
  selected="$(noctalia msg wallpaper-get 2>/dev/null || true)"
  selected="${selected%%$'\n'*}"
else
  # Image edits do not change the parent directory's mtime.
  sig="$( { find -L "$dir" -mindepth 1 -maxdepth 1 -type d -printf 'D:%p\0';
             find -L "$dir" -mindepth 2 -maxdepth 2 -type f \( "${image_filter[@]}" \) -printf 'F:%p %T@ %C@ %s\0'; } | sort -z | hash)"
  selected="$(cat "$STATE_FILE" 2>/dev/null || true)"
fi

emit_rows() { jq -c --arg s "$selected" '{items:., selected:$s}' "$rowjson" > "$out"; }
if [[ -f $sigfile && $(<"$sigfile") == "$sig" && -s $rowjson ]]; then
  valid=true
  if jq -e 'type == "array"' "$rowjson" >/dev/null 2>&1; then
    while IFS= read -r -d '' thumb; do
      [[ -s $thumb ]] || { valid=false; break; }
    done < <(jq -j '.[] | .thumb, "\u0000"' "$rowjson")
    if $valid; then emit_rows; exit 0; fi
  fi
fi

# A placeholder must work even without the optional ImageMagick dependency.
placeholder="$CACHE/folders/placeholder.svg"
if [[ ! -s $placeholder ]]; then
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="768" height="432"><rect width="768" height="432" fill="#222222"/><text x="384" y="216" fill="#aaaaaa" text-anchor="middle" font-size="30">no images yet</text></svg>' > "$placeholder"
fi

thumbnail() {
  local source="$1" kind="$2" key target part mime
  key="$( { printf '%s\0' "$source"; stat -Lc '%y %z %s' -- "$source"; } | hash)"
  target="$CACHE/$kind/$key.jpg"
  if [[ ! -s $target ]]; then
    part="$target.part.jpg"
    case "${source,,}" in
      *.mp4|*.mkv|*.webm|*.mov)
        ffmpegthumbnailer -q 6 -s 768 -i "$source" -o "$part" -c jpeg 2>/dev/null || { rm -f -- "$part"; return 1; } ;;
      *)
        vipsthumbnail "$source" --size 768x432 --smartcrop=centre -o "${part}[Q=82,strip]" >/dev/null 2>&1 || { rm -f -- "$part"; return 1; } ;;
    esac
    mime="$(file -b --mime-type -- "$part")"
    [[ $mime == image/* ]] || { rm -f -- "$part"; return 1; }
    mv -- "$part" "$target"
  fi
  printf '%s' "$target"
}

cache_complete=true
if [[ $mode == wallpaper ]]; then
  while IFS= read -r -d '' source; do
    thumb="$(thumbnail "$source" wallpapers)" || { cache_complete=false; continue; }
    base="${source##*/}"
    printf '%s\0%s\0%s\0' "$source" "$thumb" "${base%.*}" >> "$rows"
  done < <(find -L "$dir" -maxdepth 1 -type f \( "${media_filter[@]}" \) -print0 | sort -z)
else
  while IFS= read -r -d '' folder; do
    first=""
    IFS= read -r -d '' first < <(find -L "$folder" -maxdepth 1 -type f \( "${image_filter[@]}" \) -print0 | sort -z) || true
    thumb="$placeholder"
    if [[ -n $first ]]; then
      thumb="$(thumbnail "$first" folders)" || { thumb="$placeholder"; cache_complete=false; }
    fi
    printf '%s\0%s\0%s\0' "$folder" "$thumb" "${folder##*/}" >> "$rows"
  done < <(find -L "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

# Encode once, avoiding an ever-growing JSON array copied once per image.
jq -Rs 'split("\u0000") | .[:-1] | . as $v |
  [range(0; length; 3) as $i | {path:$v[$i], thumb:$v[$i+1], label:$v[$i+2]}]' "$rows" > "$rows.json"
printf '%s' "$sig" > "$rows.sig"
mv -- "$rows.json" "$rowjson"
if $cache_complete; then
  mv -- "$rows.sig" "$sigfile"
else
  # Retry failed decodes/missing optional video tools on the next opening.
  rm -f -- "$sigfile"
fi
emit_rows
