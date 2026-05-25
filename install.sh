#!/usr/bin/env bash
# MikuPlymouth Dynamic Installer - hardened
# Picks random clips from the pool and installs the theme safely.

set -euo pipefail
IFS=$'\n\t'

trap 'rc=$?; echo "Error: command \"${BASH_COMMAND}\" failed at line ${LINENO} (exit $rc)" >&2; exit $rc' ERR

# Defaults
REBUILD_INITRAMFS=1
PICK_COUNT_DEFAULT=10
PICK_COUNT="$PICK_COUNT_DEFAULT"

usage() {
    echo "Usage: $0 [--no-initramfs] [--pick-count N]" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-initramfs)
            REBUILD_INITRAMFS=0; shift ;;
        --pick-count)
            if [[ -n "${2-}" && "$2" =~ ^[0-9]+$ ]]; then PICK_COUNT="$2"; shift 2; else echo "Invalid --pick-count value" >&2; usage; fi ;;
        --pick-count=*) PICK_COUNT="${1#*=}"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown arg: $1" >&2; usage ;;
    esac
done

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (e.g., sudo ./install.sh)" >&2
    exit 1
fi

# Resolve script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
POOL_DIR="$SCRIPT_DIR/miku_plymouth_clip_pool"
THEME_DIR_LOCAL="$SCRIPT_DIR/MikuPlymouth"
THEME_DIR_SYS="/usr/share/plymouth/themes/MikuPlymouth"
THEME_NAME="MikuPlymouth"

if [ ! -d "$POOL_DIR" ]; then
    echo "Error: pool directory not found: $POOL_DIR" >&2
    exit 1
fi

# Canonicalize paths where possible
if command -v readlink >/dev/null 2>&1; then
    POOL_DIR="$(readlink -f "$POOL_DIR")"
    SCRIPT_DIR="$(readlink -f "$SCRIPT_DIR")"
    THEME_DIR_LOCAL="$(readlink -f "$THEME_DIR_LOCAL" 2>/dev/null || printf "%s" "$THEME_DIR_LOCAL")"
    THEME_DIR_SYS_PARENT="$(readlink -f "$(dirname "$THEME_DIR_SYS")")"
    THEME_DIR_SYS="$THEME_DIR_SYS_PARENT/$(basename "$THEME_DIR_SYS")"
fi

ensure_within() {
    local dir="$1" prefix="$2" real
    real="$(readlink -f "$dir" 2>/dev/null || printf "%s" "$dir")"
    case "$real" in
        "$prefix" | "$prefix"/*) return 0 ;;
        *) echo "Refusing to operate outside '$prefix': $real" >&2; exit 1 ;;
    esac
}

ensure_within "$POOL_DIR" "$SCRIPT_DIR"
ensure_within "${THEME_DIR_LOCAL:-$SCRIPT_DIR}" "$SCRIPT_DIR"
ensure_within "$THEME_DIR_SYS" "/usr/share/plymouth/themes"

echo "Step 1: Preparing local theme folder..."
mkdir -p -- "$THEME_DIR_LOCAL"

# Remove existing local PNGs safely
shopt -s nullglob
old_local_pngs=("$THEME_DIR_LOCAL"/*.png)
if (( ${#old_local_pngs[@]} )); then
    for f in "${old_local_pngs[@]}"; do rm -f -- "$f"; done
fi
shopt -u nullglob

echo "Step 2: Discovering clips in pool..."
declare -A clip_set=()
shopt -s nullglob
for f in "$POOL_DIR"/clip*_frame*.png; do
    [[ -f "$f" ]] || continue
    bn="$(basename "$f")"
    if [[ "$bn" =~ ^(clip[0-9]{3})_frame([0-9]+)\.png$ ]]; then
        clip_set["${BASH_REMATCH[1]}"]=1
    fi
done
shopt -u nullglob

available_clips=( "${!clip_set[@]}" )
if [ "${#available_clips[@]}" -eq 0 ]; then
    echo "No clips found in pool. Exiting." >&2
    exit 1
fi

IFS=$'\n' available_clips=( $(printf '%s\n' "${available_clips[@]}" | LC_ALL=C sort -V) )
num_available=${#available_clips[@]}

if [ "$num_available" -lt "$PICK_COUNT" ]; then
    PICK_COUNT="$num_available"
fi

echo "Selecting $PICK_COUNT clips (from $num_available available)..."
if command -v shuf >/dev/null 2>&1; then
    mapfile -t selected_clips < <(printf '%s\n' "${available_clips[@]}" | shuf -n "$PICK_COUNT" | LC_ALL=C sort -V)
else
    mapfile -t selected_clips < <(printf '%s\n' "${available_clips[@]}")
    # fallback shuffle
    for i in "${!selected_clips[@]}"; do
        j=$((RANDOM % ${#selected_clips[@]}))
        tmp="${selected_clips[i]}"; selected_clips[i]="${selected_clips[j]}"; selected_clips[j]="$tmp"
    done
    selected_clips=( "${selected_clips[@]:0:$PICK_COUNT}" )
    IFS=$'\n' selected_clips=( $(printf '%s\n' "${selected_clips[@]}" | LC_ALL=C sort -V) )
fi

echo "Selected: ${selected_clips[*]}"

declare -a clip_ids=()
declare -a clip_frames=()

echo "Step 3: Copying frames for selected clips..."
for clip in "${selected_clips[@]}"; do
    id_raw="${clip#clip}"
    id=$((10#$id_raw))
    frame_count=0
    shopt -s nullglob
    mapfile -t frames_sorted < <(printf '%s\n' "$POOL_DIR/${clip}_frame"*.png | LC_ALL=C sort -V)
    for ff in "${frames_sorted[@]}"; do
        [[ -f "$ff" ]] || continue
        cp -- "$ff" "$THEME_DIR_LOCAL/"
        frame_count=$((frame_count + 1))
    done
    shopt -u nullglob

    if [ "$frame_count" -le 0 ]; then
        echo "Warning: $clip has no frames; skipping." >&2
        continue
    fi

    clip_ids+=("$id")
    clip_frames+=("$frame_count")
    echo "Copied $frame_count frames for $clip (id $id)."
done

if [ "${#clip_ids[@]}" -eq 0 ]; then
    echo "No valid clips selected; aborting." >&2
    exit 1
fi

echo "Step 4: Generating MikuPlymouth.script..."
cat > "$THEME_DIR_LOCAL/MikuPlymouth.script" <<'SCRIPT_HDR'
# MikuPlymouth.script - Dynamically Generated
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

# Configuration
SCRIPT_HDR

for i in "${!clip_ids[@]}"; do
    printf 'clip_list[%d] = %s;\n' "$i" "${clip_ids[$i]}" >> "$THEME_DIR_LOCAL/MikuPlymouth.script"
    printf 'clip_frames[%d] = %s;\n' "$i" "${clip_frames[$i]}" >> "$THEME_DIR_LOCAL/MikuPlymouth.script"
done

selected_count=${#clip_ids[@]}

cat >> "$THEME_DIR_LOCAL/MikuPlymouth.script" <<'SCRIPT_BODY'
total_clips = TOTAL_CLIPS_PLACEHOLDER;

fun pad3(n) {
    if (n < 10) return "00" + n;
    if (n < 100) return "0" + n;
    return "" + n;
}

# Playback timing (dynamic)
frame_rate = 24.0;
tick_rate = 60.0;
ticks_per_frame = tick_rate / frame_rate;

# Shuffle once at start
for (i = total_clips - 1; i > 0; i--) {
    j = Math.Int(Math.Random() * (i + 1));
    temp = clip_list[i];
    clip_list[i] = clip_list[j];
    clip_list[j] = temp;
    temp_f = clip_frames[i];
    clip_frames[i] = clip_frames[j];
    clip_frames[j] = temp_f;
}

# Pre-load the first frame for instant display
first_id = clip_list[0];
miku_sprite = Sprite();
first_img = Image("clip" + pad3(first_id) + "_frame1.png");
miku_sprite.SetImage(first_img);

# Position
screen.w = Window.GetWidth(0);
screen.h = Window.GetHeight(0);
miku_sprite.SetX(Window.GetX() + (screen.w / 2 - first_img.GetWidth() / 2));
miku_sprite.SetY(Window.GetY() + (screen.h / 2 - first_img.GetHeight() / 2));

# Pre-load all frames
frame_ptr = 0;
for (c = 0; c < total_clips; c++) {
    t_id = clip_list[c];
    t_frames = clip_frames[c];
    clip_start_idx[c] = frame_ptr;
    for (f = 0; f < t_frames; f++) {
        img[frame_ptr + f] = Image("clip" + pad3(t_id) + "_frame" + (f + 1) + ".png");
    }
    frame_ptr += t_frames;
}

cur_idx = 0;
progress = 0;

fun refresh_callback () {
    frame_in_clip = Math.Int(progress / ticks_per_frame);
    if (frame_in_clip >= clip_frames[cur_idx]) frame_in_clip = clip_frames[cur_idx] - 1;
    miku_sprite.SetImage(img[clip_start_idx[cur_idx] + frame_in_clip]);
    progress++;
    total_ticks_for_clip = clip_frames[cur_idx] * ticks_per_frame;
    if (progress >= total_ticks_for_clip) {
        progress = 0;
        cur_idx = (cur_idx + 1) % total_clips;
    }
}
Plymouth.SetRefreshFunction(refresh_callback);

# Boilerplate
fun DisplayQuestionCallback(p,e){} Plymouth.SetDisplayQuestionFunction(DisplayQuestionCallback);
fun DisplayPasswordCallback(n,b){} Plymouth.SetDisplayPasswordFunction(DisplayPasswordCallback);
fun DisplayNormalCallback(){} Plymouth.SetDisplayNormalFunction(DisplayNormalCallback);
fun MessageCallback(t){} Plymouth.SetMessageFunction(MessageCallback);
SCRIPT_BODY

# Replace placeholder with actual count
sed -i "s/TOTAL_CLIPS_PLACEHOLDER/$selected_count/" "$THEME_DIR_LOCAL/MikuPlymouth.script"

echo "Step 5: Copying .plymouth if present..."
if [ -f "$SCRIPT_DIR/MikuPlymouth.plymouth" ]; then
    cp -- "$SCRIPT_DIR/MikuPlymouth.plymouth" "$THEME_DIR_LOCAL/"
elif [ -f "$POOL_DIR/MikuPlymouth.plymouth" ]; then
    cp -- "$POOL_DIR/MikuPlymouth.plymouth" "$THEME_DIR_LOCAL/"
fi

echo "Step 6: Installing to system theme directory..."
mkdir -p -- "$THEME_DIR_SYS"

# Remove existing system PNGs safely
shopt -s nullglob
old_sys_pngs=("$THEME_DIR_SYS"/*.png)
if (( ${#old_sys_pngs[@]} )); then
    for f in "${old_sys_pngs[@]}"; do rm -f -- "$f"; done
fi
shopt -u nullglob

# Copy only relevant files (png, script, plymouth)
files_to_copy=()
for f in "$THEME_DIR_LOCAL"/*; do
    case "$f" in
        *.png|*.script|*.plymouth) files_to_copy+=("$f") ;;
    esac
done
if (( ${#files_to_copy[@]} )); then
    cp -- "${files_to_copy[@]}" "$THEME_DIR_SYS/"
else
    echo "No files to install from $THEME_DIR_LOCAL" >&2
fi

echo "Step 7: Fixing ownership and permissions (conservative)..."
# Target both the system theme dir and the /opt installation path if present
targets=( "$THEME_DIR_SYS" "/opt/MikuPlymouth" "$SCRIPT_DIR" )
for t in "${targets[@]}"; do
    if [ -d "$t" ]; then
        echo "Setting owner root:root and permissions for $t"
        chown -R root:root "$t" || true
        find "$t" -type d -exec chmod 0755 {} + || true
        find "$t" -type f -exec chmod 0644 {} + || true
    fi
done

if [ "$REBUILD_INITRAMFS" -eq 1 ]; then
    echo "Step 8: Rebuilding initramfs (requested)..."
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        plymouth-set-default-theme -R "$THEME_NAME" || true
    fi

    if command -v dracut >/dev/null 2>&1; then
        dracut --force || true
    elif command -v mkinitcpio >/dev/null 2>&1; then
        mkinitcpio -P || true
    elif command -v update-initramfs >/dev/null 2>&1; then
        update-initramfs -u -k all || true
    else
        echo "Warning: No known initramfs generator found." >&2
    fi
else
    echo "Skipping initramfs rebuild (invoked with --no-initramfs)."
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        plymouth-set-default-theme "$THEME_NAME" || true
    fi
fi

echo "Done! Reboot to see MIKU."
