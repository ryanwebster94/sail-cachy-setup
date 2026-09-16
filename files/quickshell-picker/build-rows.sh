#!/bin/bash
# Build picker rows for a mode and write the JSON consumed by shell.qml.
# usage: build-rows.sh <wallpaper|folder> [dir] <out.json>
#   wallpaper: list images inside [dir] (default: passed by caller)
#   folder:    list one level of subfolders inside [dir] (default: ~/Pictures),
#              using a representative image (or placeholder) as each folder's card.
set -euo pipefail

mode="$1"
dir="${2:-}"
out="$3"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/qs-picker"
PICKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/qs-picker/folder.current"
mkdir -p "$CACHE/wallpapers" "$CACHE/folders"

placeholder="$CACHE/folders/placeholder.png"
if [[ ! -s $placeholder ]]; then
  magick -size 768x432 xc:"#1a1b26" -fill "#3b4261" \
    -draw "roundrectangle 0,0 767,431 16,16" \
    -fill "#565f89" -stroke none -gravity center -pointsize 30 \
    -annotate 0 "no images yet" "$placeholder" 2>/dev/null || true
fi

fatsig() {
  find -L "$1" -maxdepth 1 -type f -printf '%T@ %s %f\n' 2>/dev/null | cksum | cut -d' ' -f1
}

imgext='-iname *.png -o -iname *.jpg -o -iname *.jpeg -o -iname *.gif -o -iname *.bmp -o -iname *.webp'
videoext='-iname *.mp4 -o -iname *.mkv -o -iname *.webm -o -iname *.mov'

wallpaper_rows() {
  [[ -n $dir && -d $dir ]] || dir="$HOME/Pictures"

  local sig lastsig rowjson sigfile items selected f base thumb label dkey
  dkey="$(printf %s "$dir" | cksum | awk '{print $1}')"
  rowjson="$CACHE/rows-wallpaper.$dkey.json"
  sigfile="$CACHE/rows-wallpaper.$dkey.sig"
  sig="$(fatsig "$dir")"
  lastsig=""
  [[ -f $sigfile ]] && lastsig="$(<"$sigfile")"
  selected="$(noctalia msg wallpaper-get 2>/dev/null | head -1)"
  if [[ $sig == "$lastsig" && -s $rowjson ]]; then
    jq -nc --argjson a "$(cat "$rowjson")" --arg s "$selected" '{items:$a, selected:$s}' > "$out"
    return
  fi

  items="[]"
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    label="${base%.*}"
    thumb="$CACHE/wallpapers/$(printf %s "$f" | cksum | awk '{print $1}').jpg"
    if [[ ! -s $thumb ]] || ! file -b --mime-type "$thumb" 2>/dev/null | grep -q '^image/'; then
      rm -f "$thumb"
      if file -b "$f" | grep -qi 'video\|Media'; then
        ffmpegthumbnailer -q 6 -s 768 -i "$f" -o "$thumb.vpart" -c png 2>/dev/null || continue
        mv "$thumb.vpart" "$thumb"
      else
        vipsthumbnail "$f" --size 768x432 --smartcrop=centre --path "$thumb[Q=82,strip]" >/dev/null 2>&1 || continue
      fi
      file -b --mime-type "$thumb" 2>/dev/null | grep -q '^image/' || { rm -f "$thumb"; continue; }
    fi
    items="$(jq -c --arg p "$f" --arg t "$thumb" --arg l "$label" '. + [{path:$p, thumb:$t, label:$l}]' <<<"$items")"
  done < <(find -L "$dir" -maxdepth 1 -type f \( $imgext -o $videoext \) -print0 | sort -z)

  printf '%s' "$items" > "$rowjson"
  printf '%s' "$sig" > "$sigfile"
  jq -nc --argjson a "$items" --arg s "$selected" '{items:$a, selected:$s}' > "$out"
}

folder_rows() {
  [[ -n $dir && -d $dir ]] || dir="$HOME/Pictures"

  local sig lastsig rowjson sigfile items selected fd firstimg thumb label dkey
  dkey="$(printf %s "$dir" | cksum | awk '{print $1}')"
  rowjson="$CACHE/rows-folders.$dkey.json"
  sigfile="$CACHE/rows-folders.$dkey.sig"
  sig="$( {
    find -L "$dir" -maxdepth 1 -type f -printf 'B:%T@ %s %f\n' 2>/dev/null
    find -L "$dir" -maxdepth 1 -mindepth 1 -type d -printf 'D:%T@ %f\n' 2>/dev/null
  } | cksum | awk '{print $1}')"
  lastsig=""
  [[ -f $sigfile ]] && lastsig="$(<"$sigfile")"
  selected="$(cat "$STATE_FILE" 2>/dev/null || true)"
  if [[ $sig == "$lastsig" && -s $rowjson ]]; then
    jq -nc --argjson a "$(cat "$rowjson")" --arg s "$selected" '{items:$a, selected:$s}' > "$out"
    return
  fi

  items="[]"
  while IFS= read -r -d '' fd; do
    label="$(basename "$fd")"
    firstimg="$(find -L "$fd" -maxdepth 1 -type f \( $imgext \) -print 2>/dev/null | sort | head -1)"
    if [[ -n $firstimg ]]; then
      thumb="$CACHE/folders/$(printf %s "$fd" | cksum | awk '{print $1}').jpg"
      if [[ ! -s $thumb ]] || ! file -b --mime-type "$thumb" 2>/dev/null | grep -q '^image/'; then
        rm -f "$thumb"
        vipsthumbnail "$firstimg" --size 768x432 --smartcrop=centre --path "$thumb[Q=82,strip]" >/dev/null 2>&1 || true
      fi
      [[ -s $thumb && -f $thumb ]] || thumb="$placeholder"
    else
      thumb="$placeholder"
    fi
    items="$(jq -c --arg p "$fd" --arg t "$thumb" --arg l "$label" '. + [{path:$p, thumb:$t, label:$l}]' <<<"$items")"
  done < <(find -L "$dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

  printf '%s' "$items" > "$rowjson"
  printf '%s' "$sig" > "$sigfile"
  jq -nc --argjson a "$items" --arg s "$selected" '{items:$a, selected:$s}' > "$out"
}

case "$mode" in
  wallpaper) wallpaper_rows ;;
  folder) folder_rows ;;
  *) echo "unknown mode: $mode" >&2; exit 1 ;;
esac