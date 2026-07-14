#!/bin/sh
# Derive DogeOS branding assets from img/ sources into config/includes*.
# Requires ImageMagick (magick).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LOGO="${ROOT}/img/doge-logo.png"
LOGIN="${ROOT}/img/login.png"
OUT="${ROOT}/assets/branding"
BG_DST="${ROOT}/config/includes.chroot/usr/share/backgrounds/dogeos"
PROP_DST="${ROOT}/config/includes.chroot/usr/share/gnome-background-properties"

if [ ! -f "$LOGO" ]; then
	echo "error: missing source logo: $LOGO" >&2
	exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
	echo "error: ImageMagick 'magick' not found" >&2
	exit 1
fi

# PNG24 8-bit RGB from LOGO — safe for GRUB / plymouth / installer.
png24_logo() {
	size=$1
	out=$2
	magick "$LOGO" -colorspace sRGB -background black -alpha remove -alpha off \
		-resize "${size}" -strip -depth 8 -type TrueColor \
		-define png:color-type=2 PNG24:"$out"
}

logo_on_black() {
	canvas=$1
	logo_max=$2
	out=$3
	magick "$LOGO" -colorspace sRGB -background black -alpha remove -alpha off \
		-resize "${logo_max}" \
		\( -size "$canvas" xc:black \) +swap -gravity center -compose over -composite \
		-strip -depth 8 -type TrueColor -define png:color-type=2 PNG24:"$out"
}

icon_transparent() {
	size=$1
	out=$2
	magick "$LOGO" -colorspace sRGB \
		-fuzz 8% -transparent black \
		-resize "${size}" -strip -depth 8 PNG32:"$out"
}

# Full-bleed image → GRUB-safe PNG24 (8-bit RGB, no alpha).
grub_png_from() {
	src=$1
	size=$2
	out=$3
	magick "$src" -colorspace sRGB -alpha remove -alpha off \
		-resize "${size}^" -gravity center -extent "${size}" \
		-strip -depth 8 -type TrueColor -define png:color-type=2 PNG24:"$out"
}

# Cap huge photos for ISO size (max long edge).
wallpaper_for_iso() {
	src=$1
	out=$2
	max_edge=${3:-3840}
	magick "$src" -colorspace sRGB \
		-resize "${max_edge}x${max_edge}>" \
		-strip -quality 90 "$out"
}

mkdir -p \
	"$OUT" \
	"$OUT/icons" \
	"$BG_DST" \
	"$PROP_DST" \
	"${ROOT}/config/bootloaders/grub-pc" \
	"${ROOT}/config/includes.chroot/usr/share/plymouth/themes/doge" \
	"${ROOT}/config/includes.installer/usr/share/graphics" \
	"${ROOT}/config/includes.chroot/usr/share/pixmaps" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/32x32/apps" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/48x48/apps" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/128x128/apps" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/256x256/apps" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/512x512/apps"

echo "Generating logo-derived assets from $LOGO ..."

png24_logo 512x512 "$OUT/doge-logo.png"
cp -f "$OUT/doge-logo.png" "${ROOT}/config/includes.chroot/usr/share/pixmaps/dogeos-logo.png"

icon_transparent 32x32 "$OUT/icons/dogeos-32.png"
icon_transparent 48x48 "$OUT/icons/dogeos-48.png"
icon_transparent 128x128 "$OUT/icons/dogeos-128.png"
icon_transparent 256x256 "$OUT/icons/dogeos-256.png"
icon_transparent 512x512 "$OUT/icons/dogeos-512.png"

cp -f "$OUT/icons/dogeos-32.png" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/32x32/apps/dogeos.png"
cp -f "$OUT/icons/dogeos-48.png" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/48x48/apps/dogeos.png"
cp -f "$OUT/icons/dogeos-128.png" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/128x128/apps/dogeos.png"
cp -f "$OUT/icons/dogeos-256.png" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/256x256/apps/dogeos.png"
cp -f "$OUT/icons/dogeos-512.png" \
	"${ROOT}/config/includes.chroot/usr/share/icons/hicolor/512x512/apps/dogeos.png"

logo_on_black 800x600 360x360 "${ROOT}/config/bootloaders/grub-pc/splash.png"
cp -f "${ROOT}/config/bootloaders/grub-pc/splash.png" "$OUT/grub-splash-800x600.png"

png24_logo 256x256 "${ROOT}/config/includes.chroot/usr/share/plymouth/themes/doge/logo.png"
cp -f "${ROOT}/config/includes.chroot/usr/share/plymouth/themes/doge/logo.png" \
	"$OUT/plymouth-logo-256.png"

png24_logo 64x64 "${ROOT}/config/includes.installer/usr/share/graphics/logo_debian.png"
cp -f "${ROOT}/config/includes.installer/usr/share/graphics/logo_debian.png" \
	"$OUT/installer-logo-64.png"

# --- Login + wallpapers + installed GRUB backgrounds ---
if [ -f "$LOGIN" ]; then
	echo "Using login/wallpaper sources ..."
	# GDM login (keep 1920x1080 PNG; normalize strip/depth)
	magick "$LOGIN" -colorspace sRGB -strip -depth 8 "$BG_DST/login.png"
	cp -f "$BG_DST/login.png" "$OUT/login.png"

	# Installed GRUB backgrounds from login art
	grub_png_from "$LOGIN" 1920x1080 "$BG_DST/grub-16x9.png"
	grub_png_from "$LOGIN" 1024x768 "$BG_DST/grub-4x3.png"
	cp -f "$BG_DST/grub-16x9.png" "$OUT/grub-16x9.png"
	cp -f "$BG_DST/grub-4x3.png" "$OUT/grub-4x3.png"
	rm -f "$OUT/grub-16x9-temp.png" "$OUT/grub-4x3-temp.png"
else
	echo "warning: $LOGIN missing — keeping logo-on-black GRUB temps" >&2
	logo_on_black 1920x1080 512x512 "$BG_DST/grub-16x9.png"
	logo_on_black 1024x768 420x420 "$BG_DST/grub-4x3.png"
fi

i=1
for src in "${ROOT}/img"/wallpaper-*.jpg "${ROOT}/img"/wallpaper-*.png; do
	[ -f "$src" ] || continue
	base=$(basename "$src")
	ext=${base##*.}
	out_name="wallpaper-${i}.${ext}"
	# Prefer jpeg output for size when source is jpg
	case "$ext" in
		jpg|jpeg|JPG|JPEG)
			out_name="wallpaper-${i}.jpg"
			wallpaper_for_iso "$src" "$BG_DST/$out_name" 3840
			;;
		*)
			out_name="wallpaper-${i}.png"
			wallpaper_for_iso "$src" "$BG_DST/$out_name" 3840
			;;
	esac
	cp -f "$BG_DST/$out_name" "$OUT/$out_name"
	i=$((i + 1))
done

# GNOME default wallpaper = wallpaper-4 (see 90_doge-background.gschema.override)
DEFAULT_WP="$BG_DST/wallpaper-4.jpg"
[ -f "$DEFAULT_WP" ] || DEFAULT_WP="$BG_DST/login.png"

cat > "$PROP_DST/dogeos-wallpapers.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
EOF

if [ -f "$BG_DST/login.png" ]; then
	cat >> "$PROP_DST/dogeos-wallpapers.xml" <<'EOF'
  <wallpaper deleted="false">
    <name>DogeOS Login</name>
    <filename>/usr/share/backgrounds/dogeos/login.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
EOF
fi

n=1
for f in "$BG_DST"/wallpaper-*; do
	[ -f "$f" ] || continue
	bn=$(basename "$f")
	cat >> "$PROP_DST/dogeos-wallpapers.xml" <<EOF
  <wallpaper deleted="false">
    <name>DogeOS Wallpaper ${n}</name>
    <filename>/usr/share/backgrounds/dogeos/${bn}</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
EOF
	n=$((n + 1))
done

cat >> "$PROP_DST/dogeos-wallpapers.xml" <<'EOF'
</wallpapers>
EOF

echo "Done."
echo "Backgrounds:"
ls -lh "$BG_DST" 2>/dev/null || true
file "${ROOT}/config/bootloaders/grub-pc/splash.png" \
	"$BG_DST/login.png" \
	"$BG_DST/grub-16x9.png" \
	"${ROOT}/config/includes.chroot/usr/share/plymouth/themes/doge/logo.png" 2>/dev/null || true
