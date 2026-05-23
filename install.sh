#!/bin/bash
# MikuPlymouth Dynamic Installer
# This script picks 10 random clips from the pool and sets them up.

POOL_DIR="miku_plymouth_clip_pool"
THEME_DIR_LOCAL="MikuPlymouth"
THEME_DIR_SYS="/usr/share/plymouth/themes/MikuPlymouth"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"

if [ ! -d "$POOL_DIR" ]; then
    echo "Error: $POOL_DIR not found!"
    exit 1
fi

echo "Step 1: Cleaning up local theme folder..."
mkdir -p "$THEME_DIR_LOCAL"
rm -f "$THEME_DIR_LOCAL"/*.png

echo "Step 2: Picking 10 random clips from the pool..."
# Get unique clip numbers from the pool
available_clips=$(ls "$POOL_DIR" | grep -o 'clip[0-9]*' | sort -u)
# Shuffle and pick 10
selected_clips=$(echo "$available_clips" | shuf -n 10 | sort)

echo "Selected clips: $(echo $selected_clips | xargs)"

# Store IDs for the script generation
clip_ids=()
for clip in $selected_clips; do
    id=$(echo "$clip" | sed 's/clip0*//')
    # If id is empty (was clip000), set to 0
    if [ -z "$id" ]; then id=0; fi
    clip_ids+=($id)
    
    echo "Copying $clip..."
    cp "$POOL_DIR/${clip}_frame"* "$THEME_DIR_LOCAL/"
done

echo "Step 3: Generating MikuPlymouth.script..."
cat << EOF > "$THEME_DIR_LOCAL/MikuPlymouth.script"
# MikuPlymouth.script - Dynamically Generated
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

# Configuration (The 10 clips chosen by the installer)
EOF

# Add the clip IDs to the script
i=0
for id in "${clip_ids[@]}"; do
    echo "clip_list[$i] = $id;" >> "$THEME_DIR_LOCAL/MikuPlymouth.script"
    i=$((i+1))
done

cat << 'EOF' >> "$THEME_DIR_LOCAL/MikuPlymouth.script"
total_clips = 10;
fps = 24;

# Shuffle once at start
for (i = total_clips - 1; i > 0; i--) {
    j = Math.Int(Math.Random() * (i + 1));
    temp = clip_list[i];
    clip_list[i] = clip_list[j];
    clip_list[j] = temp;
}

# Pre-load the first frame for instant display
first_id = clip_list[0];
if (first_id < 10) f_str = "00" + first_id; else f_str = "0" + first_id;

miku_sprite = Sprite();
first_img = Image("clip" + f_str + "_frame1.png");
miku_sprite.SetImage(first_img);

# Position
screen.w = Window.GetWidth(0);
screen.h = Window.GetHeight(0);
miku_sprite.SetX(Window.GetX() + (screen.w / 2 - first_img.GetWidth() / 2));
miku_sprite.SetY(Window.GetY() + (screen.h / 2 - first_img.GetHeight() / 2));

# Pre-load all frames (10 * 24 = 240 frames)
for (c = 0; c < total_clips; c++) {
    t_id = clip_list[c];
    if (t_id < 10) t_str = "00" + t_id; else t_str = "0" + t_id;
    for (f = 0; f < 24; f++) {
        img[c * 24 + f] = Image("clip" + t_str + "_frame" + (f + 1) + ".png");
    }
}

cur_idx = 0;
progress = 0;

fun refresh_callback () {
    tick = progress % 60;
    f_idx = Math.Int(tick * 0.4);
    
    miku_sprite.SetImage(img[cur_idx * 24 + f_idx]);
    progress++;
    
    if (progress % 60 == 0) {
        cur_idx = (cur_idx + 1) % total_clips;
    }
}
Plymouth.SetRefreshFunction(refresh_callback);

# Boilerplate
fun DisplayQuestionCallback(p,e){} Plymouth.SetDisplayQuestionFunction(DisplayQuestionCallback);
fun DisplayPasswordCallback(n,b){} Plymouth.SetDisplayPasswordFunction(DisplayPasswordCallback);
fun DisplayNormalCallback(){} Plymouth.SetDisplayNormalFunction(DisplayNormalCallback);
fun MessageCallback(t){} Plymouth.SetMessageFunction(MessageCallback);
EOF

echo "Step 4: Installing to system..."
sudo mkdir -p "$THEME_DIR_SYS"
sudo rm -f "$THEME_DIR_SYS"/*.png
sudo cp "$THEME_DIR_LOCAL"/* "$THEME_DIR_SYS/"

echo "Step 5: Rebuilding initramfs..."
sudo plymouth-set-default-theme -R MikuPlymouth

if command -v dracut &> /dev/null; then
    # Works on Fedora, CachyOS, openSUSE
    echo "Dracut detected..."
    sudo dracut --force
elif command -v mkinitcpio &> /dev/null; then
    # Works on Arch, Manjaro
    echo "mkinitcpio detected..."
    sudo mkinitcpio -P
elif command -v update-initramfs &> /dev/null; then
    # Works on Ubuntu, Debian, Mint
    echo "initramfs detected..."
    sudo update-initramfs -u -k all
else
    echo "Warning: No known initramfs generator found."
    echo "Please rebuild your initramfs manually to see the theme on boot."
fi

echo "Done! Picked 10 clips and installed. Reboot to see MIKU."
