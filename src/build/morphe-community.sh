#!/bin/bash
# Morphe Community build (manifest-driven via src/targets.json)
source ./src/build/utils.sh

TARGETS_MANIFEST="./src/targets.json"
use_beta="${use_beta:-false}"

if [ "$use_beta" = false ]; then
	tag="latest"
else
	tag="prerelease"
fi

separate_morphe_universal_patches=true

morphe_universal_dl() {
	local patches_tag="${1:-$tag}"
	dl_gh "morphe-patches" "MorpheApp" "$patches_tag" "true"
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
	dl_gh "$repo" "$org" "$custom_tag"
}

community_patch() {
	patch "$1" "$2" "morphe"
	if [ "${detachPlayStoreUpdates:-false}" = true ]; then
		if ! ls morphe-universal-*.mpp.disabled >/dev/null 2>&1; then
			morphe_universal_dl
		fi
		morphe_disable_play_store_updates "$1" "$2"
	fi
	unset detachPlayStoreUpdates
}

_download_target_apk() {
	local pkg="$1" apk_name="$2" apk_type="$3" arch="$4" dpi="$5" minver="$6" fallback_uptodown="$7"
	if [[ "$fallback_uptodown" == "true" ]]; then
		get_apk "$pkg" "$apk_name" "$apk_type" "$arch" "$dpi" "$minver" || \
		get_apk_uptodown "$pkg" "$apk_name" "$apk_type"
	else
		get_apk "$pkg" "$apk_name" "$apk_type" "$arch" "$dpi" "$minver"
	fi
}

# Reusable single-bundle community app builder
build_community_app() {
	local target_json="$1"

	APP_NAME=$(jq -r '.app_name' <<< "$target_json")
	VARIANT=$(jq -r '.variant' <<< "$target_json")
	OMIT_PATCH_VERSION=$(jq -r 'if .omit_patch_version then "true" else "false" end' <<< "$target_json")
	local pkg patches_dir auto_discover force_detach
	pkg=$(jq -r '.package' <<< "$target_json")
	patches_dir=$(jq -r '.patches_dir' <<< "$target_json")
	auto_discover=$(jq -r 'if .auto_discover then "true" else "false" end' <<< "$target_json")
	force_detach=$(jq -r 'if .detach_play_store then "true" else "false" end' <<< "$target_json")

	local src_repo src_owner src_name src_tag
	src_repo=$(jq -r '.sources[0].repo' <<< "$target_json")
	src_owner="${src_repo%%/*}"
	src_name="${src_repo#*/}"
	src_tag=$(jq -r '.sources[0].tag_mode // ""' <<< "$target_json")
	[[ "$use_beta" == "true" || -z "$src_tag" ]] && src_tag="$tag"

	local apk_name apk_type arch dpi minver fallback_uptodown
	apk_name=$(jq -r '.apk.name' <<< "$target_json")
	apk_type=$(jq -r '.apk.type // "apk"' <<< "$target_json")
	arch=$(jq -r '.apk.arch // ""' <<< "$target_json")
	dpi=$(jq -r '.apk.dpi // ""' <<< "$target_json")
	minver=$(jq -r '.apk.minver // ""' <<< "$target_json")
	fallback_uptodown=$(jq -r 'if .apk.fallback_uptodown then "true" else "false" end' <<< "$target_json")

	export APP_NAME VARIANT OMIT_PATCH_VERSION
	if [ -n "$GITHUB_ENV" ]; then
		echo "APP_NAME=$APP_NAME" >> "$GITHUB_ENV"
		echo "VARIANT=$VARIANT" >> "$GITHUB_ENV"
		[[ "$OMIT_PATCH_VERSION" == "true" ]] && echo "OMIT_PATCH_VERSION=true" >> "$GITHUB_ENV"
	fi

	community_dl "$src_name" "$src_owner" "$src_tag"
	get_patches_key "$patches_dir"
	_download_target_apk "$pkg" "$apk_name" "$apk_type" "$arch" "$dpi" "$minver" "$fallback_uptodown"

	release_exists && return 0

	if [[ "$auto_discover" == "true" ]]; then
		auto_include_community_patches "$pkg" "$patches_dir"
	fi
	if [[ "$force_detach" == "true" ]]; then
		detachPlayStoreUpdates=true
	fi
	community_patch "$apk_name" "$VARIANT"
}

# Reusable multi-source / dual-bundle fusion app builder (e.g. reddit-adobo)
build_fusion_app() {
	local target_json="$1"

	APP_NAME=$(jq -r '.app_name' <<< "$target_json")
	VARIANT=$(jq -r '.variant' <<< "$target_json")
	OMIT_PATCH_VERSION=$(jq -r 'if .omit_patch_version then "true" else "false" end' <<< "$target_json")
	local pkg patches_dir auto_discover
	pkg=$(jq -r '.package' <<< "$target_json")
	patches_dir=$(jq -r '.patches_dir' <<< "$target_json")
	auto_discover=$(jq -r 'if .auto_discover then "true" else "false" end' <<< "$target_json")

	local apk_name out_name apk_type arch dpi minver split_exclude fallback_uptodown
	apk_name=$(jq -r '.apk.name' <<< "$target_json")
	out_name=$(jq -r '.apk.out_name // .apk.name' <<< "$target_json")
	apk_type=$(jq -r '.apk.type // "apk"' <<< "$target_json")
	arch=$(jq -r '.apk.arch // ""' <<< "$target_json")
	dpi=$(jq -r '.apk.dpi // ""' <<< "$target_json")
	minver=$(jq -r '.apk.minver // ""' <<< "$target_json")
	split_exclude=$(jq -r '.apk.split_exclude // ""' <<< "$target_json")
	fallback_uptodown=$(jq -r 'if .apk.fallback_uptodown then "true" else "false" end' <<< "$target_json")

	export APP_NAME VARIANT OMIT_PATCH_VERSION
	if [ -n "$GITHUB_ENV" ]; then
		echo "APP_NAME=$APP_NAME" >> "$GITHUB_ENV"
		echo "VARIANT=$VARIANT" >> "$GITHUB_ENV"
		[[ "$OMIT_PATCH_VERSION" == "true" ]] && echo "OMIT_PATCH_VERSION=true" >> "$GITHUB_ENV"
	fi

	dl_gh "morphe-desktop" "MorpheApp" "$tag" "true"

	local combined_parts=()
	local src_count idx
	src_count=$(jq '.sources | length' <<< "$target_json")
	for (( idx = 0; idx < src_count; idx++ )); do
		local s_repo s_owner s_name s_tag s_role s_prefix s_ver=""
		s_repo=$(jq -r ".sources[$idx].repo" <<< "$target_json")
		s_owner="${s_repo%%/*}"
		s_name="${s_repo#*/}"
		s_tag=$(jq -r ".sources[$idx].tag_mode // \"\"" <<< "$target_json")
		s_role=$(jq -r ".sources[$idx].role // \"community\"" <<< "$target_json")
		s_prefix=$(jq -r ".sources[$idx].version_prefix // \"\"" <<< "$target_json")
		[[ "$use_beta" == "true" || -z "$s_tag" ]] && s_tag="$tag"

		if [[ "$s_role" == "morphe" ]]; then
			morphe_universal_dl "$s_tag"
			local f
			for f in morphe-universal-*.mpp*; do
				[ -e "$f" ] && s_ver=$(get_patch_version_from_asset_name "$f") && break
			done
		else
			patch_version=""
			dl_gh "$s_name" "$s_owner" "$s_tag"
			s_ver="$patch_version"
		fi

		if [[ -n "$s_prefix" && -n "$s_ver" ]]; then
			combined_parts+=("${s_prefix}${s_ver}")
		fi
	done

	if [[ ${#combined_parts[@]} -eq $src_count && $src_count -gt 1 ]]; then
		local IFS="-"
		patch_version="${combined_parts[*]}"
		unset IFS
		export patch_version
		[ -n "$GITHUB_ENV" ] && echo "patch_version=$patch_version" >> "$GITHUB_ENV"
		green_log "[+] Combined fusion patch version: $patch_version"
	fi

	get_patches_key "$patches_dir"
	_download_target_apk "$pkg" "$apk_name" "$apk_type" "$arch" "$dpi" "$minver" "$fallback_uptodown"

	release_exists && return 0

	if [[ -n "$split_exclude" ]]; then
		split_editor "$apk_name" "$out_name" "exclude" "$split_exclude"
	fi

	# Re-enable Morphe universal bundle for single-pass fusion patching
	local patches_file
	for patches_file in morphe-universal-*.mpp.disabled; do
		[ -e "$patches_file" ] || continue
		mv "$patches_file" "${patches_file%.disabled}"
	done
	separate_morphe_universal_patches=false
	get_patches_key "$patches_dir"
	if [[ "$auto_discover" == "true" ]]; then
		auto_include_community_patches "$pkg" "$patches_dir"
	fi
	patch "$out_name" "$VARIANT" "morphe"
}

# ==============================================================================
# Custom Builders (Non-Morphe Resource Patching)
# ==============================================================================

_find_android_build_tool() {
	local tool="$1"
	if command -v "$tool" >/dev/null 2>&1; then
		command -v "$tool"
		return 0
	fi
	local sdk_root
	for sdk_root in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "/usr/local/lib/android/sdk"; do
		[ -n "$sdk_root" ] && [ -d "$sdk_root/build-tools" ] || continue
		local found
		found=$(find "$sdk_root/build-tools" -maxdepth 2 -type f -name "$tool" 2>/dev/null | sort -V | tail -n1)
		if [ -n "$found" ] && [ -x "$found" ]; then
			printf '%s' "$found"
			return 0
		fi
	done
	return 1
}

niagram() {
	APP_NAME="niagram"
	VARIANT="premium-icon"
	[ -n "$GITHUB_ENV" ] && echo "APP_NAME=$APP_NAME" >> "$GITHUB_ENV"
	[ -n "$GITHUB_ENV" ] && echo "VARIANT=$VARIANT" >> "$GITHUB_ENV"

	local auth_header=()
	[ -n "$GITHUB_TOKEN" ] && auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")
	local releases_json
	if command -v curl >/dev/null 2>&1; then
		releases_json=$(curl -sSL "${auth_header[@]}" "https://api.github.com/repos/HSSkyBoy/Niagram/releases?per_page=10")
	else
		local auth_wget=()
		[ -n "$GITHUB_TOKEN" ] && auth_wget=(--header="Authorization: Bearer $GITHUB_TOKEN")
		releases_json=$(wget -qO- "${auth_wget[@]}" "https://api.github.com/repos/HSSkyBoy/Niagram/releases?per_page=10")
	fi

	local release_filter='.[]'
	if [ "$use_beta" = false ]; then
		release_filter='.[] | select(.prerelease == false)'
	fi

	local release_tag apk_url asset_name
	release_tag=$(echo "$releases_json" | jq -r "first($release_filter | select(.assets[]?.name | test(\"-arm64-v8a\\\\.apk$\"))) | .tag_name")
	apk_url=$(echo "$releases_json" | jq -r "first($release_filter | .assets[] | select(.name | test(\"-arm64-v8a\\\\.apk$\"))) | .browser_download_url")
	asset_name=$(echo "$releases_json" | jq -r "first($release_filter | .assets[] | select(.name | test(\"-arm64-v8a\\\\.apk$\"))) | .name")

	if [[ -z "$apk_url" || "$apk_url" == "null" ]]; then
		red_log "[-] Could not find Niagram arm64-v8a.apk in HSSkyBoy/Niagram releases"
		exit 1
	fi

	if [[ "$asset_name" =~ Niagram-v([0-9]+(\.[0-9]+)+) ]]; then
		version="${BASH_REMATCH[1]}"
	else
		version="$release_tag"
	fi
	patch_version="${release_tag#v}"
	[[ -z "$patch_version" || "$patch_version" == "null" ]] && patch_version="1.0.0"

	export version patch_version
	export_app_version "$version"
	[ -n "$GITHUB_ENV" ] && echo "patch_version=$patch_version" >> "$GITHUB_ENV"
	green_log "[+] Target Niagram version: $version (build $patch_version, $asset_name)"

	release_exists && return 0

	mkdir -p ./download ./release
	green_log "[+] Downloading $asset_name from HSSkyBoy/Niagram"
	if command -v curl >/dev/null 2>&1; then
		curl -sSL -o "./download/niagram-arm64-v8a.apk" "$apk_url"
	else
		wget -q -O "./download/niagram-arm64-v8a.apk" "$apk_url"
	fi

	ensure_apkeditor
	local dec_dir="./download/niagram-dec"
	local unaligned_apk="./download/niagram-arm64-v8a-unaligned.apk"
	local aligned_apk="./download/niagram-arm64-v8a-aligned.apk"
	local output_apk="./release/niagram-arm64-v8a-${VARIANT}.apk"

	green_log "[+] Decoding Niagram resources with APKEditor"
	if ! java -jar "$APKEditor" d -f -dex -t xml -i "./download/niagram-arm64-v8a.apk" -o "$dec_dir"; then
		red_log "[-] APKEditor decode failed for Niagram"
		exit 1
	fi

	green_log "[+] Applying Telegram Premium Star launcher & notification branding"
	if ! python3 ./src/build/helper/patch_niagram_branding.py "$dec_dir" "./src/patches/niagram/icons"; then
		red_log "[-] Failed to patch Niagram branding resources"
		exit 1
	fi

	green_log "[+] Rebuilding Niagram APK with APKEditor"
	if ! java -jar "$APKEditor" b -f -i "$dec_dir" -o "$unaligned_apk"; then
		red_log "[-] APKEditor rebuild failed for Niagram"
		exit 1
	fi

	local zipalign_bin apksigner_bin
	if ! zipalign_bin=$(_find_android_build_tool "zipalign"); then
		red_log "[-] zipalign not found in PATH or Android SDK build-tools"
		exit 1
	fi
	if ! apksigner_bin=$(_find_android_build_tool "apksigner"); then
		red_log "[-] apksigner not found in PATH or Android SDK build-tools"
		exit 1
	fi

	green_log "[+] Aligning and signing $output_apk"
	"$zipalign_bin" -p -f 4 "$unaligned_apk" "$aligned_apk"
	if ! "$apksigner_bin" sign \
		--ks ./src/lspatch-signing.p12 \
		--ks-type PKCS12 \
		--ks-pass pass:morphe \
		--ks-key-alias fiorenmas \
		--key-pass pass:morphe \
		--out "$output_apk" \
		"$aligned_apk"; then
		red_log "[-] apksigner failed for Niagram"
		exit 1
	fi
	"$apksigner_bin" verify "$output_apk"
	rm -rf "$dec_dir" "$unaligned_apk" "$aligned_apk"
	green_log "[+] Built $output_apk"
}

# ==============================================================================
# Manifest-Driven Dispatcher
# ==============================================================================

dispatch_target() {
	local requested="$1"
	if [[ -z "$requested" ]]; then
		red_log "[-] No target specified"
		exit 1
	fi

	local target_json
	target_json=$(jq -c --arg req "$requested" '
		first(.targets[] | select(.org == "Morphe-Community") | select(.id == $req or ((.aliases // []) | index($req)))) // empty
	' "$TARGETS_MANIFEST")

	if [[ -z "$target_json" ]]; then
		red_log "[-] Unknown community target: $requested"
		exit 1
	fi

	local custom_builder is_fusion
	custom_builder=$(jq -r '.custom_builder // ""' <<< "$target_json")
	is_fusion=$(jq -r 'if .fusion then "true" else "false" end' <<< "$target_json")

	if [[ -n "$custom_builder" ]]; then
		"$custom_builder"
	elif [[ "$is_fusion" == "true" ]]; then
		build_fusion_app "$target_json"
	else
		build_community_app "$target_json"
	fi
}

dispatch_target "$1"
