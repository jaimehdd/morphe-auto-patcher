#!/bin/bash
# Morphe Community build
source ./src/build/utils.sh

use_beta="${use_beta:-false}"

if [ "$use_beta" = false ]; then
	tag="latest"
else
	tag="prerelease"
fi

separate_morphe_universal_patches=true

morphe_universal_dl() {
	dl_gh "morphe-patches" "MorpheApp" "$tag"
	for patches_file in patches-*.mpp; do
		[ -e "$patches_file" ] || continue
		mv "$patches_file" "morphe-universal-$patches_file.disabled"
	done
}

community_dl() {
	local repo="$1"
	local org="$2"
	local custom_tag="${3:-$tag}"

	dl_gh "morphe-desktop" "MorpheApp" "latest"
	morphe_universal_dl
	dl_gh "$repo" "$org" "$custom_tag"
}

community_patch() {
	patch "$1" "$2" "morphe"
	if [ "${detachPlayStoreUpdates:-false}" = true ]; then
		morphe_disable_play_store_updates "$1" "$2"
	fi
	unset detachPlayStoreUpdates
}

# ==============================================================================
# Group 1: SysAdminDoc Hush Suite
# ==============================================================================

facebook() {
	APP_NAME="facebook"
	VARIANT="hushfacebook"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "HushFacebook" "SysAdminDoc"
	get_patches_key "facebook"
	get_apk "com.facebook.katana" "facebook-arm64-v8a" "bundle" "arm64-v8a" "320-640dpi" "Android 11+"

	release_exists && return 0

	auto_include_community_patches "com.facebook.katana" "facebook"
	detachPlayStoreUpdates=true
	community_patch "facebook-arm64-v8a" "hushfacebook"
}
facebook-hushfacebook() { facebook; }

messenger() {
	APP_NAME="messenger"
	VARIANT="hushmessenger"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "HushMessenger" "SysAdminDoc"
	get_patches_key "messenger"
	get_apk "com.facebook.orca" "messenger-arm64-v8a" "apk" "arm64-v8a" "nodpi" "Android 9.0+"

	release_exists && return 0

	auto_include_community_patches "com.facebook.orca" "messenger"
	detachPlayStoreUpdates=true
	community_patch "messenger-arm64-v8a" "hushmessenger"
}
messenger-hushmessenger() { messenger; }

instagram() {
	APP_NAME="instagram"
	VARIANT="hushgram"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "HushGram" "SysAdminDoc"
	get_patches_key "instagram"
	get_apk "com.instagram.android" "instagram-arm64-v8a" "bundle" "arm64-v8a" "480-640dpi" "Android 9.0+"

	release_exists && return 0

	auto_include_community_patches "com.instagram.android" "instagram"
	detachPlayStoreUpdates=true
	community_patch "instagram-arm64-v8a" "hushgram"
}
instagram-hushgram() { instagram; }

tiktok() {
	APP_NAME="tiktok"
	VARIANT="hushfeed"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "hushfeed" "SysAdminDoc"
	get_patches_key "tiktok"
	get_apk "com.zhiliaoapp.musically" "tiktok-arm64-v8a" "apk" "arm64-v8a" || \
	get_apk_uptodown "com.zhiliaoapp.musically" "tiktok-arm64-v8a" "apk"

	release_exists && return 0

	auto_include_community_patches "com.zhiliaoapp.musically" "tiktok"
	community_patch "tiktok-arm64-v8a" "hushfeed"
}

telegram() {
	APP_NAME="telegram"
	VARIANT="hushtelegram"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "HushTelegram" "SysAdminDoc"
	get_patches_key "telegram"
	get_apk "org.telegram.messenger.web" "telegram-arm64-v8a" "apk" "universal"

	release_exists && return 0

	auto_include_community_patches "org.telegram.messenger.web" "telegram"

	if [[ -n "$TELEGRAM_API_ID" && -n "$TELEGRAM_API_HASH" ]]; then
		green_log "[+] Applying registered Telegram API credentials (ID: $TELEGRAM_API_ID)"
		local jar_file
		jar_file=$(ls morphe-desktop-*.jar 2>/dev/null | head -n1)
		local mpp_file
		mpp_file=$(ls patches-*.mpp 2>/dev/null | head -n1)

		if [[ -n "$jar_file" && -n "$mpp_file" ]]; then
			java -jar "$jar_file" options-create --patches "$mpp_file" --filter-package-name org.telegram.messenger.web --out ./src/options/hushtelegram.json 2>/dev/null || true
		fi

		python3 -c '
import json, sys, os, glob

api_id = sys.argv[1].strip()
api_hash = sys.argv[2].strip()
options_path = "./src/options/hushtelegram.json"

data = []
if os.path.exists(options_path):
    try:
        with open(options_path, "r") as f:
            data = json.load(f)
    except Exception:
        data = []

if not isinstance(data, list) or len(data) == 0:
    mpp_files = glob.glob("patches-*.mpp")
    source_name = os.path.basename(mpp_files[0]) if mpp_files else "patches-0.0.20.mpp"
    data = [{
        "meta": {"source": source_name},
        "patches": {}
    }]

for bundle in data:
    patches = bundle.setdefault("patches", {})
    entry = patches.setdefault("Use registered Telegram API credentials", {})
    entry["enabled"] = True
    entry["options"] = {
        "apiId": str(api_id),
        "apiHash": str(api_hash)
    }

with open(options_path, "w") as f:
    json.dump(data, f, indent=2)
print("[+] Successfully configured apiId and apiHash in " + options_path)
' "$TELEGRAM_API_ID" "$TELEGRAM_API_HASH"

		if [[ "$communityIncludePatches" != *"-e \"Use registered Telegram API credentials\""* ]]; then
			communityIncludePatches+=" -e \"Use registered Telegram API credentials\""
		fi
	else
		communityIncludePatches="${communityIncludePatches//-e \"Use registered Telegram API credentials\"/}"
		communityExcludePatches+=" -d \"Use registered Telegram API credentials\""
	fi

	# Suppress launcher context menu shortcut for HushTelegram
	green_log "[+] Suppressing launcher context menu shortcut in HushTelegram extension"
	python3 -c '
import zipfile, struct, hashlib, zlib, os, glob

mpp_files = glob.glob("patches-*.mpp")
if not mpp_files:
    exit(0)

mpp_path = mpp_files[0]
target_entry = "extensions/telegram.mpe"

with zipfile.ZipFile(mpp_path, "r") as z:
    if target_entry not in z.namelist():
        exit(0)
    dex = bytearray(z.read(target_entry))

string_ids_size, string_ids_off = struct.unpack("<II", dex[56:64])
type_ids_size, type_ids_off = struct.unpack("<II", dex[64:72])
method_ids_size, method_ids_off = struct.unpack("<II", dex[88:96])
class_defs_size, class_defs_off = struct.unpack("<II", dex[96:104])

def get_string(idx):
    off, = struct.unpack("<I", dex[string_ids_off + idx * 4 : string_ids_off + idx * 4 + 4])
    pos = off; l = 0; shift = 0
    while True:
        b = dex[pos]; pos += 1
        l |= (b & 0x7f) << shift
        if (b & 0x80) == 0: break
        shift += 7
    return dex[pos:pos+l].decode("latin1", "replace")

def get_type(idx):
    str_idx, = struct.unpack("<I", dex[type_ids_off + idx * 4 : type_ids_off + idx * 4 + 4])
    return get_string(str_idx)

modified = 0
for i in range(class_defs_size):
    c_off = class_defs_off + i * 32
    class_idx, access_flags, superclass_idx, interfaces_off, source_file_idx, annotations_off, class_data_off, static_values_off = struct.unpack("<IIIIIIII", dex[c_off:c_off+32])
    if get_type(class_idx) == "Lapp/hushtelegram/extension/telegram/settings/SettingsEntry;":
        cursor = [class_data_off]
        def read_uleb128():
            res = 0; shift = 0
            while True:
                b = dex[cursor[0]]; cursor[0] += 1
                res |= (b & 0x7f) << shift
                if (b & 0x80) == 0: break
                shift += 7
            return res
        s_fields = read_uleb128(); i_fields = read_uleb128(); d_methods = read_uleb128(); v_methods = read_uleb128()
        for _ in range(s_fields): read_uleb128(); read_uleb128()
        for _ in range(i_fields): read_uleb128(); read_uleb128()
        m_idx = 0
        for _ in range(d_methods + v_methods):
            m_diff = read_uleb128(); m_idx += m_diff; m_flags = read_uleb128(); m_code = read_uleb128()
            m_def = dex[method_ids_off + m_idx * 8 : method_ids_off + m_idx * 8 + 8]
            _, _, n_idx = struct.unpack("<HHI", m_def)
            m_name = get_string(n_idx)
            if m_name in ("publishShortcut", "publishShortcutNow"):
                insn_start = m_code + 16
                dex[insn_start] = 0x0e
                dex[insn_start + 1] = 0x00
                modified += 1

if modified > 0:
    new_sig = hashlib.sha1(dex[32:]).digest()
    dex[12:32] = new_sig
    new_checksum = zlib.adler32(dex[12:]) & 0xffffffff
    dex[8:12] = struct.pack("<I", new_checksum)

    temp_zip = mpp_path + ".tmp"
    with zipfile.ZipFile(mpp_path, "r") as zin, zipfile.ZipFile(temp_zip, "w") as zout:
        for item in zin.infolist():
            if item.filename == target_entry:
                zout.writestr(item, dex)
            else:
                zout.writestr(item, zin.read(item.filename))
    os.replace(temp_zip, mpp_path)
    print(f"[+] Successfully neutralized {modified} launcher shortcut registration methods")
'

	community_patch "telegram-arm64-v8a" "hushtelegram"

	if [[ -n "$TELEGRAM_API_ID" && -n "$TELEGRAM_API_HASH" ]]; then
		python3 -c '
import zipfile, sys

apk_path = sys.argv[1]
api_hash = sys.argv[2].encode("ascii")

found = False
with zipfile.ZipFile(apk_path) as z:
    for name in z.namelist():
        if name.endswith(".dex"):
            if api_hash in z.read(name):
                found = True
                break

if not found:
    print("[-] ERROR: Registered Telegram API credentials were NOT applied to APK!", file=sys.stderr)
    sys.exit(1)
print("[+] Verification passed: Registered Telegram API credentials confirmed in patched APK.")
' "./release/telegram-arm64-v8a-hushtelegram.apk" "$TELEGRAM_API_HASH"
	fi

	python3 -c '
import zipfile, struct, sys

apk_path = "./release/telegram-arm64-v8a-hushtelegram.apk"
verified = False

with zipfile.ZipFile(apk_path) as z:
    for dex_name in z.namelist():
        if not dex_name.endswith(".dex"): continue
        dex = z.read(dex_name)
        if b"Lapp/hushtelegram/extension/telegram/settings/SettingsEntry;" not in dex: continue
        string_ids_size, string_ids_off = struct.unpack("<II", dex[56:64])
        type_ids_size, type_ids_off = struct.unpack("<II", dex[64:72])
        method_ids_size, method_ids_off = struct.unpack("<II", dex[88:96])
        class_defs_size, class_defs_off = struct.unpack("<II", dex[96:104])

        def get_string(idx):
            off, = struct.unpack("<I", dex[string_ids_off + idx * 4 : string_ids_off + idx * 4 + 4])
            pos = off; l = 0; shift = 0
            while True:
                b = dex[pos]; pos += 1
                l |= (b & 0x7f) << shift
                if (b & 0x80) == 0: break
                shift += 7
            return dex[pos:pos+l].decode("latin1", "replace")

        def get_type(idx):
            str_idx, = struct.unpack("<I", dex[type_ids_off + idx * 4 : type_ids_off + idx * 4 + 4])
            return get_string(str_idx)

        for i in range(class_defs_size):
            c_off = class_defs_off + i * 32
            class_idx, access_flags, superclass_idx, interfaces_off, source_file_idx, annotations_off, class_data_off, static_values_off = struct.unpack("<IIIIIIII", dex[c_off:c_off+32])
            if get_type(class_idx) == "Lapp/hushtelegram/extension/telegram/settings/SettingsEntry;":
                cursor = [class_data_off]
                def read_uleb128():
                    res = 0; shift = 0
                    while True:
                        b = dex[cursor[0]]; cursor[0] += 1
                        res |= (b & 0x7f) << shift
                        if (b & 0x80) == 0: break
                        shift += 7
                    return res
                s_fields = read_uleb128(); i_fields = read_uleb128(); d_methods = read_uleb128(); v_methods = read_uleb128()
                for _ in range(s_fields): read_uleb128(); read_uleb128()
                for _ in range(i_fields): read_uleb128(); read_uleb128()
                m_idx = 0
                for _ in range(d_methods + v_methods):
                    m_diff = read_uleb128(); m_idx += m_diff; m_flags = read_uleb128(); m_code = read_uleb128()
                    m_def = dex[method_ids_off + m_idx * 8 : method_ids_off + m_idx * 8 + 8]
                    _, _, n_idx = struct.unpack("<HHI", m_def)
                    m_name = get_string(n_idx)
                    if m_name == "publishShortcut":
                        insn = dex[m_code + 16 : m_code + 18]
                        if insn == b"\x0e\x00":
                            verified = True

if verified:
    print("[+] Verification passed: Launcher shortcut publish method verified neutralized (return-void) in APK.")
else:
    print("[!] Warning: Launcher shortcut publish method was not neutralized in final APK.")
'
}
telegram-hushtelegram() { telegram; }

# ==============================================================================
# Group 2: Media, Audio & Photos
# ==============================================================================

photos() {
	APP_NAME="google-photos"
	VARIANT="akash-sriram"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-google-photos" "Akash-Sriram"
	get_patches_key "gg-photos"
	get_apk "com.google.android.apps.photos" "gg-photos-arm64-v8a" "apk"

	release_exists && return 0

	community_patch "gg-photos-arm64-v8a" "akash-sriram"
}

poweramp() {
	APP_NAME="poweramp"
	VARIANT="hooman"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "hoomans-morphe-patches" "arandomhooman"
	get_patches_key "poweramp"
	get_apk "com.maxmpz.audioplayer" "poweramp" "bundle"

	release_exists && return 0

	community_patch "poweramp" "hooman"
}

moonreader() {
	APP_NAME="moonreader"
	VARIANT="binarymend"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "binarymend"
	get_patches_key "moonreader"
	get_apk "com.flyersoft.moonreader" "moonreader-arm64-v8a" "bundle"

	release_exists && return 0

	community_patch "moonreader-arm64-v8a" "binarymend"
}

readera() {
	APP_NAME="readera"
	VARIANT="hxreborn"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "hxreborn"
	get_patches_key "readera"
	get_apk "org.readera" "readera-arm64-v8a" "bundle"

	release_exists && return 0

	community_patch "readera-arm64-v8a" "hxreborn"
}

# ==============================================================================
# Group 3: Sports, Fitness & Navigation
# ==============================================================================

fotmob() {
	APP_NAME="fotmob"
	VARIANT="hoo-dles"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "hoo-dles"
	get_patches_key "fotmob"
	get_apk "com.mobilefootie.wc2010" "fotmob-arm64-v8a" "bundle" "universal" "nodpi" "Android 12L+"

	release_exists && return 0

	community_patch "fotmob-arm64-v8a" "hoo-dles"
}

komoot() {
	APP_NAME="komoot"
	VARIANT="rushi"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "rushiranpise"
	get_patches_key "komoot"
	get_apk "de.komoot.android" "komoot-arm64-v8a" "bundle"

	release_exists && return 0

	community_patch "komoot-arm64-v8a" "rushi"
}

strava() {
	APP_NAME="strava"
	VARIANT="rushi"
	# echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	# echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	# community_dl "morphe-patches" "rushiranpise"
	# get_patches_key "strava"
	# get_apk_uptodown "com.strava" "strava-arm64-v8a" "bundle"

	# release_exists && return 0

	# community_patch "strava-arm64-v8a" "rushi"
}

# ==============================================================================
# Group 4: Browsing, Adblocking & Weather
# ==============================================================================

adguard() {
	APP_NAME="adguard"
	VARIANT="rushi"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "rushiranpise"
	get_patches_key "adguard"
	get_apk "com.adguard.android" "adguard" "apk"

	release_exists && return 0

	community_patch "adguard" "rushi"
}

brave() {
	APP_NAME="brave"
	VARIANT="dh6k"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "dh6k"
	get_patches_key "brave"
	get_apk "com.brave.browser" "brave-arm64-v8a" "bundle" "arm64-v8a"

	release_exists && return 0

	community_patch "brave-arm64-v8a" "dh6k"
}

windy() {
	APP_NAME="windy"
	VARIANT="rushi"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "morphe-patches" "rushiranpise"
	get_patches_key "windy"
	get_apk "com.windyty.android" "windy-arm64-v8a" "bundle" "universal" "120-640dpi" "Android 12L+"

	release_exists && return 0

	community_patch "windy-arm64-v8a" "rushi"
}

# ==============================================================================
# Group 5: Community UI Mod Clients
# ==============================================================================

reddit-adobo() {
	APP_NAME="reddit"
	VARIANT="adobo"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "adobo" "jkennethcarino" "prerelease"
	get_patches_key "reddit-adobo"
	get_apk "com.reddit.frontpage" "reddit" "bundle_extract"

	release_exists && return 0

	# Patch Arm64-v8a:
	split_editor "reddit" "reddit-arm64-v8a" "exclude" "split_config.armeabi_v7a split_config.x86_64 split_config.mdpi split_config.ldpi split_config.hdpi split_config.xhdpi split_config.xxhdpi split_config.tvdpi"
	for patches_file in morphe-universal-*.mpp.disabled; do
		[ -e "$patches_file" ] || continue
		mv "$patches_file" "${patches_file%.disabled}"
	done
	separate_morphe_universal_patches=false
	get_patches_key "reddit-adobo"
	patch "reddit-arm64-v8a" "adobo" "morphe"
}

linkedin() {
	APP_NAME="linkedin"
	VARIANT="michii"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "michii-patches" "heyymichii"
	get_patches_key "linkedin"
	get_apk "com.linkedin.android" "linkedin-arm64-v8a" "bundle" "arm64-v8a"

	release_exists && return 0

	community_patch "linkedin-arm64-v8a" "michii"
}

# ==============================================================================
# Dispatcher
# ==============================================================================

case "$1" in
	facebook|facebook-hushfacebook)
		facebook
		;;
	messenger|messenger-hushmessenger)
		messenger
		;;
	instagram|instagram-hushgram)
		instagram
		;;
	tiktok|tiktok-hushfeed)
		tiktok
		;;
	photos|google-photos)
		photos
		;;
	poweramp)
		poweramp
		;;
	moonreader)
		moonreader
		;;
	readera|readera-hxreborn)
		readera
		;;
	fotmob)
		fotmob
		;;
	komoot)
		komoot
		;;
	strava)
		strava
		;;
	adguard)
		adguard
		;;
	brave)
		brave
		;;
	windy)
		windy
		;;
	reddit-adobo|reddit)
		reddit-adobo
		;;
	linkedin|linkedin-michii)
		linkedin
		;;
	telegram|telegram-hushtelegram)
		telegram
		;;
esac
