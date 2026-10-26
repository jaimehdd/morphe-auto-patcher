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
	dl_gh "morphe-patches" "MorpheApp" "$tag" "true"
	for patches_file in patches-*.mpp; do
		[ -e "$patches_file" ] || continue
		mv "$patches_file" "morphe-universal-$patches_file.disabled"
	done
}

community_dl() {
	local repo="$1"
	local org="$2"
	local custom_tag="${3:-$tag}"

	dl_gh "morphe-desktop" "MorpheApp" "$tag" "true"
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
	VARIANT="heval"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "Heval-Morphe-Patches" "heval99"
	get_patches_key "fotmob"
	get_apk "com.mobilefootie.wc2010" "fotmob-arm64-v8a" "bundle" "universal" "nodpi" "Android 12L+"

	release_exists && return 0

	community_patch "fotmob-arm64-v8a" "heval"
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

nagramxf() {
	APP_NAME="nagramxf"
	VARIANT="shini-cell"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	community_dl "shini-morphe" "shini-cell"
	get_patches_key "nagramxf"

	# Detect compatible version from shini-morphe patch bundle
	detect_version "fork.risin42.nagramx"

	local auth_header=()
	[ -n "$GITHUB_TOKEN" ] && auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")
	local releases_json
	if command -v curl >/dev/null 2>&1; then
		releases_json=$(curl -sSL "${auth_header[@]}" "https://api.github.com/repos/Keeperorowner/NagramXF/releases?per_page=10")
	else
		local auth_wget=()
		[ -n "$GITHUB_TOKEN" ] && auth_wget=(--header="Authorization: Bearer $GITHUB_TOKEN")
		releases_json=$(wget -qO- "${auth_wget[@]}" "https://api.github.com/repos/Keeperorowner/NagramXF/releases?per_page=10")
	fi

	local apk_url="" asset_name=""
	if [[ -n "$version" ]]; then
		apk_url=$(echo "$releases_json" | jq -r --arg ver "$version" '.[] | .assets[] | select(.name | (test($ver) and test("(normal-)?arm64-v8a\\.apk$"))) | .browser_download_url' | head -n1)
		asset_name=$(echo "$releases_json" | jq -r --arg ver "$version" '.[] | .assets[] | select(.name | (test($ver) and test("(normal-)?arm64-v8a\\.apk$"))) | .name' | head -n1)
	fi

	if [[ -z "$apk_url" || "$apk_url" == "null" ]]; then
		apk_url=$(echo "$releases_json" | jq -r 'first(.[] | .assets[] | select(.name | test("(normal-)?arm64-v8a\\.apk$"))) | .browser_download_url')
		asset_name=$(echo "$releases_json" | jq -r 'first(.[] | .assets[] | select(.name | test("(normal-)?arm64-v8a\\.apk$"))) | .name')
	fi

	if [[ -z "$apk_url" || "$apk_url" == "null" ]]; then
		red_log "[-] Could not find NagramXF arm64-v8a.apk in Keeperorowner/NagramXF releases"
		exit 1
	fi

	if [[ "$asset_name" =~ NagramXF-v([0-9]+(\.[0-9]+)+(-[0-9a-f]+)?) ]]; then
		version="${BASH_REMATCH[1]}"
	elif [[ -z "$version" ]]; then
		version=$(echo "$releases_json" | jq -r 'first(.[]) | .tag_name')
	fi
	export version
	export_app_version "$version"
	green_log "[+] Target NagramXF version: $version ($asset_name)"

	release_exists && return 0

	mkdir -p ./download
	green_log "[+] Downloading $asset_name from Keeperorowner/NagramXF"
	if command -v curl >/dev/null 2>&1; then
		curl -sSL -o "./download/nagramxf-arm64-v8a.apk" "$apk_url"
	else
		wget -q -O "./download/nagramxf-arm64-v8a.apk" "$apk_url"
	fi

	community_patch "nagramxf-arm64-v8a" "shini-cell"
}
nagramxf-shini-cell() { nagramxf; }

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
	nagramxf|nagramxf-shini-cell)
		nagramxf
		;;
esac
