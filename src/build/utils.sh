#!/bin/bash

mkdir ./release ./download

#Setup pup for download apk files
wget -q -O ./pup.zip https://github.com/ericchiang/pup/releases/download/v0.4.0/pup_v0.4.0_linux_amd64.zip
unzip "./pup.zip" -d "./" > /dev/null 2>&1
pup="./pup"
#Setup APKEditor for install combine split apks
wget -q -O ./APKEditor.jar https://github.com/REAndroid/APKEditor/releases/download/V1.4.9/APKEditor-1.4.9.jar
APKEditor="./APKEditor.jar"
#Find lastest user_agent
user_agent=$(wget -qO- https://www.whatismybrowser.com/guides/the-latest-user-agent/firefox | tr '\n' ' ' | sed 's#</tr>#\n#g' | grep 'Firefox (Standard)' | sed -n 's/.*<span class="code">\([^<]*Android[^<]*\)<\/span>.*/\1/p') \
|| user_agent=
[ -z "$user_agent" ] && {
  user_agent='Mozilla/5.0 (Android 16; Mobile; rv:146.0) Gecko/146.0 Firefox/146.0'
  echo "[-] Can't found lastest user-agent"
}

#################################################

# Colored output logs
green_log() {
    echo -e "\e[32m$1\e[0m"
}
red_log() {
    echo -e "\e[31m$1\e[0m"
}
yellow_log() {
    echo -e "\e[33m$1\e[0m"
}

export_app_version() {
	local app_version
	app_version=$(echo "$1" | awk '{
		ver = $1
		if (ver ~ /^[0-9]+\./) {
			print ver
		} else if (match(ver, /[0-9]+(\.[0-9]+)*/)) {
			print substr(ver, RSTART, RLENGTH)
		} else {
			print ver
		}
	}')
	export APP_VERSION="$app_version"
	echo "APP_VERSION=$app_version" >> $GITHUB_ENV
	green_log "[+] APP_VERSION: ${app_version:-unknown}"
}

set_patch_version_from_asset_name() {
	local asset_name="$1"
	local detected_patch_version=""

	if [[ $asset_name == *.jar ]] && [[ $asset_name == *"revanced-patches"* ]]; then
		# arsclib jar files: revanced-patches-X.Y.Z.jar
		detected_patch_version=${asset_name#"revanced-patches-"}
		detected_patch_version=${detected_patch_version%.jar}
	elif [[ $asset_name == *.rvp ]] && [[ $asset_name == *"patches-"* ]]; then
		# rvp files: patches-X.Y.Z.rvp or revanced-patches-X.Y.Z.rvp
		if [[ $asset_name == *"revanced-patches-"* ]]; then
			detected_patch_version=${asset_name#"revanced-patches-"}
		else
			detected_patch_version=${asset_name#"patches-"}
		fi
		detected_patch_version=${detected_patch_version%.rvp}
	elif [[ $asset_name == *.mpp ]] && [[ $asset_name == *"patches-"* ]]; then
		# mpp files: patches-X.Y.Z.mpp (Morphe)
		detected_patch_version=${asset_name#"patches-"}
		detected_patch_version=${detected_patch_version%.mpp}
	elif [[ $asset_name == *"NexAlloy-"* ]] && [[ $asset_name == *.apk ]]; then
		# NexAlloy apk assets (e.g. NexAlloy-nonroot-release-v6.0.apk)
		detected_patch_version=${asset_name#NexAlloy-*-*-}
		detected_patch_version=${detected_patch_version%.apk}
		detected_patch_version=${detected_patch_version#v}
	fi

	if [[ -n "$detected_patch_version" ]]; then
		patch_version="$detected_patch_version"
		export patch_version
		echo "patch_version=$patch_version" >> $GITHUB_ENV
		green_log "Patch version: $patch_version"
	fi
}

release_exists() {
	local app_version="${APP_VERSION:-$version}"
	local repo="${repository:-$GITHUB_REPOSITORY}"
	local release_tag="${APP_NAME}-${VARIANT}-${app_version}-${patch_version}"

	if [[ "${force_patch:-false}" == "true" ]]; then
		green_log "[+] Force patch enabled, skipping existing release check"
		return 1
	fi

	if [[ -z "$APP_NAME" || -z "$VARIANT" || -z "$app_version" || -z "$patch_version" ]]; then
		red_log "[-] Missing release metadata, patching will continue"
		return 1
	fi

	if [[ -z "$repo" ]]; then
		red_log "[-] Missing repository metadata, patching will continue"
		return 1
	fi

	green_log "[+] Checking existing release: $release_tag"
	local apk_asset_count
	apk_asset_count=$(gh release view "$release_tag" --repo "$repo" --json assets --jq '[.assets[].name | select(endswith(".apk"))] | length' 2>/dev/null) || return 1

	if [[ "$apk_asset_count" -gt 0 ]]; then
		green_log "[+] Release already has APK asset(s), skipping patch: $release_tag"
		return 0
	fi

	green_log "[+] Release exists without APK assets, patching will continue: $release_tag"
	return 1
}

#################################################

# Download Github assets requirement:
dl_gh() {
  local repo=$1 owner=$2 tag_mode=$3
  local -a auth=()
  if [ -n "$GITHUB_TOKEN" ]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  local api_url
  if [ "$tag_mode" == "prerelease" ]; then
    api_url="https://api.github.com/repos/$owner/$repo/releases"
  elif [ "$tag_mode" == "latest" ]; then
    api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
  else
    api_url="https://api.github.com/repos/$owner/$repo/releases/tags/$tag_mode"
  fi

  local json
  if command -v curl >/dev/null 2>&1; then
    json=$(curl -sSL "${auth[@]}" "$api_url")
  else
    local -a auth_wget=()
    [ -n "$GITHUB_TOKEN" ] && auth_wget=(--header="Authorization: Bearer $GITHUB_TOKEN")
    json=$(wget -qO- "${auth_wget[@]}" "$api_url")
  fi

  if [[ -z "$json" ]] || [[ "$json" == *"API rate limit exceeded"* ]]; then
    red_log "[-] GitHub API request failed or rate limited for $owner/$repo"
    exit 1
  fi

  local jq_filter
  if [ "$tag_mode" == "prerelease" ]; then
    jq_filter='first(.[]) | .assets[] | "\(.browser_download_url) \(.name)"'
  else
    jq_filter='.assets[] | "\(.browser_download_url) \(.name)"'
  fi

  local downloaded=0
  while read -r url names; do
    [ -z "$url" ] && continue
    if [[ $url != *.asc ]]; then
      if [[ "$tag_mode" == "latest" && "$names" == *dev* ]]; then
        continue
      fi
      green_log "[+] Downloading $names from $owner"
      set_patch_version_from_asset_name "$names"
      if command -v curl >/dev/null 2>&1; then
        curl -sSL -o "$names" "$url"
      else
        wget -q -O "$names" "$url"
      fi
      downloaded=1
    fi
  done < <(echo "$json" | jq -r "$jq_filter" 2>/dev/null)

  if [ $downloaded -eq 0 ]; then
    red_log "[-] Failed to download any asset for $repo from $owner (mode: $tag_mode)"
    exit 1
  fi
}

dl_gl() {
  local repo=$1 owner=$2 tag=${3:-latest}
  local project_path="${owner}%2F${repo}"
  local api_url="https://gitlab.com/api/v4/projects/${project_path}/releases"

  local releases
  releases=$(wget -qO- "$api_url")

  local release
  if [[ "$tag" == "latest" ]]; then
    release=$(echo "$releases" | jq -r '[.[] | select(.tag_name | test("-dev") | not)][0]')
  elif [[ "$tag" == "prerelease" ]]; then
    release=$(echo "$releases" | jq -r '[.[] | select(.tag_name | test("-dev"))][0]')
  else
    release=$(wget -qO- "$api_url/$tag")
  fi

  if [[ -z "$release" ]] || [[ "$release" == "null" ]]; then
    red_log "[-] No matching release found for $owner/$repo ($tag)"
    return 1
  fi

  local tag_name
  tag_name=$(echo "$release" | jq -r '.tag_name')

  echo "$release" | jq -r '.assets.links[] | "\(.direct_asset_url // .url) \(.name)"' | \
    while read -r url name; do
      if [[ -n "$url" ]] && [[ "$url" != "null" ]] && [[ $url != *.asc ]]; then
        green_log "[+] Downloading $name from $owner"
        wget -q -O "$name" "$url"
      fi
    done
}

#################################################

# Get patches list:
get_patches_key() {
	excludePatches=""
	includePatches=""
	morpheExcludePatches=""
	morpheIncludePatches=""
	communityExcludePatches=""
	communityIncludePatches=""
	detachPlayStoreUpdates=false
	excludeLinesFound=false
	includeLinesFound=false

	local patchDir="src/patches/$1"
	local patch_name line1 line2 current_section

	if [ -f "$patchDir/include-patches" ]; then
		sed -i '' 's/\r$//' "$patchDir/include-patches" 2>/dev/null || sed -i 's/\r$//' "$patchDir/include-patches" 2>/dev/null || true
	fi
	if [ -f "$patchDir/exclude-patches" ]; then
		sed -i '' 's/\r$//' "$patchDir/exclude-patches" 2>/dev/null || sed -i 's/\r$//' "$patchDir/exclude-patches" 2>/dev/null || true
	fi

	# Parse exclude-patches
	current_section="default"
	if [ -f "$patchDir/exclude-patches" ]; then
		while IFS= read -r line1 || [[ -n "$line1" ]]; do
			[[ -z "$line1" ]] && continue
			if [[ "$line1" =~ ^[[:space:]]*#[[:space:]]*\[?([Mm]orphe|[Uu]niversal) ]]; then
				current_section="morphe"
				continue
			elif [[ "$line1" =~ ^[[:space:]]*#[[:space:]]*\[?([Aa]dobo|[Cc]ommunity|[Pp]iko|[Rr]ushi|[Bb]inarymend|[Hh]oo-dles|[Hh]ooman|[Dd]h6k|[Tt]ik[Tt]ok|[Aa]ndrew|[Pp]rathxm|[Hh]ushfeed|[Hh]ush[Ff]acebook|[Hh]ush[Gg]ram|[Hh]ush[Mm]essenger|[Aa]kash-[Ss]riram|[Hh]xreborn|[Mm]ichii|[Ss]hini) ]]; then
				current_section="community"
				continue
			elif [[ "$line1" =~ ^[[:space:]]*# ]]; then
				continue
			fi

			excludeLinesFound=true
			if [ "$current_section" = "morphe" ]; then
				morpheExcludePatches+=" -d \"$line1\""
			elif [ "$current_section" = "community" ]; then
				communityExcludePatches+=" -d \"$line1\""
			else
				excludePatches+=" -d \"$line1\""
			fi
		done < "$patchDir/exclude-patches"
	fi

	# Parse include-patches
	current_section="default"
	if [ -f "$patchDir/include-patches" ]; then
		while IFS= read -r line2 || [[ -n "$line2" ]]; do
			[[ -z "$line2" ]] && continue
			if [[ "$line2" =~ ^[[:space:]]*#[[:space:]]*\[?([Mm]orphe|[Uu]niversal) ]]; then
				current_section="morphe"
				continue
			elif [[ "$line2" =~ ^[[:space:]]*#[[:space:]]*\[?([Aa]dobo|[Cc]ommunity|[Pp]iko|[Rr]ushi|[Bb]inarymend|[Hh]oo-dles|[Hh]ooman|[Dd]h6k|[Tt]ik[Tt]ok|[Aa]ndrew|[Pp]rathxm|[Hh]ushfeed|[Hh]ush[Ff]acebook|[Hh]ush[Gg]ram|[Hh]ush[Mm]essenger|[Aa]kash-[Ss]riram|[Hh]xreborn|[Mm]ichii|[Ss]hini) ]]; then
				current_section="community"
				continue
			elif [[ "$line2" =~ ^[[:space:]]*# ]]; then
				continue
			fi

			patch_name="${line2%%|*}"
			local patch_opts=""
			if [[ "$line2" == *"|"* ]]; then
				local raw_opts="${line2#*|}"
				local opt
				IFS=',' read -ra opt_pairs <<< "$raw_opts"
				for opt in "${opt_pairs[@]}"; do
					opt=$(echo "$opt" | xargs)
					[[ -z "$opt" ]] && continue
					if [[ "$opt" =~ ^-O ]]; then
						patch_opts+=" $opt"
					else
						patch_opts+=" -O $opt"
					fi
				done
			fi
			includeLinesFound=true

			if [[ "${separate_morphe_universal_patches:-false}" == "true" && "$patch_name" == "Disable Play Store updates" ]]; then
				detachPlayStoreUpdates=true
				continue
			fi

			if [ "$current_section" = "morphe" ]; then
				morpheIncludePatches+=" -e \"$patch_name\"$patch_opts"
			elif [ "$current_section" = "community" ]; then
				communityIncludePatches+=" -e \"$patch_name\"$patch_opts"
			else
				includePatches+=" -e \"$patch_name\"$patch_opts"
			fi
		done < "$patchDir/include-patches"
	fi

	if [ "$excludeLinesFound" = false ]; then
		excludePatches=""
	fi
	if [ "$includeLinesFound" = false ]; then
		includePatches=""
	fi

	export excludePatches
	export includePatches
	export morpheExcludePatches
	export morpheIncludePatches
	export communityExcludePatches
	export communityIncludePatches
	export detachPlayStoreUpdates
}

#################################################

_req() {
    local cookie_args=()
    [[ -n "$FS_COOKIES" ]] && cookie_args=(--header "Cookie: $FS_COOKIES")
    if [ "$2" = "-" ]; then
        wget -nv -O "$2" --header="User-Agent: $user_agent" --header="Content-Type: application/octet-stream" --header="Accept-Language: en-US,en;q=0.9" --header="Connection: keep-alive" --header="Upgrade-Insecure-Requests: 1" --header="Cache-Control: max-age=0" --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" "${cookie_args[@]}" --keep-session-cookies --timeout=30 "$1" || rm -f "$2"
    else
        wget -nv -O "./download/$2" --header="User-Agent: $user_agent" --header="Content-Type: application/octet-stream" --header="Accept-Language: en-US,en;q=0.9" --header="Connection: keep-alive" --header="Upgrade-Insecure-Requests: 1" --header="Cache-Control: max-age=0" --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" "${cookie_args[@]}" --keep-session-cookies --timeout=30 "$1" || rm -f "./download/$2"
    fi
}
req() {
    _req "$1" "$2"
}

morphe_patches_args() {
	local option="${1:--p}" pattern="${2:-*.mpp}" args="" patches_file
	for patches_file in $pattern; do
		[ -e "$patches_file" ] || continue
		args+=" $option \"$patches_file\""
		if [[ "$patches_file" =~ morphe-universal ]]; then
			args+="$morpheExcludePatches$morpheIncludePatches"
		else
			args+="$communityExcludePatches$communityIncludePatches"
		fi
	done
	printf '%s' "$args"
}

auto_include_community_patches() {
	local pkg_name="$1"
	local patch_target="$2"
	local patch_pattern="${3:-patches-*.mpp}"
	local jar_file
	jar_file=$(ls morphe-desktop-*.jar 2>/dev/null | head -n1)

	if [[ -z "$jar_file" ]] || ! ls $patch_pattern >/dev/null 2>&1; then
		yellow_log "[!] Morphe desktop or bundle $patch_pattern not found, skipping patch auto-discovery"
		return 0
	fi

	local mpp_file
	for f in $patch_pattern; do
		[ -f "$f" ] && mpp_file="$f" && break
	done
	[ -z "$mpp_file" ] && return 0

	green_log "[+] Auto-discovering patches for $pkg_name from $mpp_file"

	local raw_patches
	raw_patches=$(java -jar "$jar_file" list-patches --patches "$mpp_file" --filter-package-name="$pkg_name" 2>/dev/null)

	local patch_name
	local included_count=0
	local excluded_count=0
	local exclude_file="src/patches/$patch_target/exclude-patches"

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		[[ "$line" =~ ^[[:space:]]*Name:[[:space:]]*(.*)$ ]] || continue
		patch_name="${BASH_REMATCH[1]}"
		patch_name="$(echo "$patch_name" | xargs)"
		[[ -z "$patch_name" ]] && continue

		# Exclusive exclusions: x86 architecture or Clone / package rename
		if [[ "$patch_name" =~ [xX]86 ]] || [[ "$patch_name" =~ [Cc]lone ]] || [[ "$patch_name" =~ [Cc]hange[[:space:]]+package[[:space:]]+name ]] || [[ "$patch_name" =~ [Ii]nstall[[:space:]]+next[[:space:]]+to ]]; then
			yellow_log "[-] Auto-excluding (exclusive rule): $patch_name"
			((excluded_count++))
			continue
		fi

		# Check if already excluded via get_patches_key or exclude-patches file
		if [[ "$communityExcludePatches" == *"-d \"$patch_name\""* ]] || \
		   [[ "$morpheExcludePatches" == *"-d \"$patch_name\""* ]] || \
		   [[ "$excludePatches" == *"-d \"$patch_name\""* ]] || \
		   { [ -f "$exclude_file" ] && grep -Fxq "$patch_name" "$exclude_file"; }; then
			yellow_log "[-] Auto-excluding (in exclude-patches): $patch_name"
			((excluded_count++))
			continue
		fi

		# Check if already included in includePatches or communityIncludePatches
		if [[ "$communityIncludePatches" == *"-e \"$patch_name\""* ]] || \
		   [[ "$includePatches" == *"-e \"$patch_name\""* ]]; then
			continue
		fi

		communityIncludePatches+=" -e \"$patch_name\""
		((included_count++))
	done <<< "$raw_patches"

	export communityIncludePatches
	green_log "[+] Patch auto-discovery complete: $included_count included, $excluded_count excluded"
}

detect_version() {
	if [ -z "$version" ] && [ "$lock_version" != "1" ]; then
	  local jar_prefix="morphe-desktop-" patch_glob="*.mpp"

	  if [[ $(ls "${jar_prefix}"*.jar 2>/dev/null) =~ ${jar_prefix}([0-9]+) ]]; then
	    local list_patches_flags="list-patches --with-packages --with-versions --with-options --patches"
	    local patches_info
	    patches_info=$(java -jar "${jar_prefix}"*.jar $list_patches_flags $patch_glob 2>/dev/null)

	    version=$(echo "$patches_info" | awk -v pkg="$1" '
		  BEGIN { found = 0; printing = 0 }
		  /^Index:/ { if (printing) exit; found = 0 }
		  /Package name: / { if ($3 == pkg) found = 1 }
		  /Compatible versions:/ { if (found) printing = 1; next }
		  printing {
		    if ($0 ~ /:/) {
		      exit
		    }
		    ver = $0
		    gsub(/^[[:space:]-]*|[[:space:]]*$/, "", ver)
		    split(ver, parts, " ")
		    first_word = parts[1]
		    if (first_word ~ /^[0-9]+\./) {
		      print first_word
		    } else {
		      print ver
		    }
		  }
		' | sort -V | tail -n1)

	    if [[ -z "$target_version_code" ]]; then
	      local auto_vcode
	      auto_vcode=$(echo "$patches_info" | awk -v pkg="$1" '
		    BEGIN { found = 0; printing = 0 }
		    /^Index:/ { if (printing) exit; found = 0 }
		    /Package name: / { if ($3 == pkg) found = 1 }
		    /Version codes:/ { if (found) printing = 1; next }
		    printing {
		      if ($0 ~ /:/) exit
		      code = $0
		      gsub(/^[[:space:]-]*|[[:space:]]*$/, "", code)
		      if (code ~ /^[0-9]+$/) print code
		    }
		  ' | sort -n | tail -n1)
	      if [[ -n "$auto_vcode" ]]; then
	        target_version_code="$auto_vcode"
	        export target_version_code
	      fi
	    fi

	    # Fallback: if target_version_code is still empty, extract version codes from .mpp Target class constant pools
	    if [[ -z "$target_version_code" && -z "$target_version_codes" ]]; then
	      local auto_vcodes
	      auto_vcodes=$(python3 -c '
import zipfile, struct, glob
codes = set()
for mpp in glob.glob("*.mpp"):
    try:
        with zipfile.ZipFile(mpp) as z:
            for name in z.namelist():
                if ("Target" in name or "Compat" in name) and name.endswith(".class"):
                    data = z.read(name)
                    if data[:4] == b"\xca\xfe\xba\xbe":
                        cp_count = struct.unpack(">H", data[8:10])[0]
                        idx = 10
                        i = 1
                        while i < cp_count:
                            tag = data[idx]
                            idx += 1
                            if tag == 1:
                                l = struct.unpack(">H", data[idx:idx+2])[0]
                                idx += 2 + l
                            elif tag == 3:
                                v = struct.unpack(">i", data[idx:idx+4])[0]
                                idx += 4
                                if 100000000 <= v < 2000000000:
                                    codes.add(v)
                            elif tag in (4, 9, 10, 11, 12, 17, 18):
                                idx += 4
                            elif tag in (5, 6):
                                idx += 8
                                i += 1
                            elif tag in (7, 8, 16, 19, 20):
                                idx += 2
                            elif tag == 15:
                                idx += 3
                            else:
                                break
                            i += 1
    except Exception:
        pass
if codes:
    print(" ".join(str(c) for c in sorted(codes)))
' 2>/dev/null)
	      if [[ -n "$auto_vcodes" ]]; then
	        target_version_codes="$auto_vcodes"
	        export target_version_codes
	        green_log "[+] Extracted supported version codes from bundle: $target_version_codes"
	      fi
	    fi
	  fi
	fi
}

_fs_get() {
	local url=$1
	local max_retries=3
	local attempt
	for attempt in $(seq 1 $max_retries); do
		local response
		response=$(curl -s -X POST 'http://localhost:8191/v1' \
			-H 'Content-Type: application/json' \
			-d "{\"cmd\":\"request.get\",\"url\":\"$url\",\"maxTimeout\":15000}")
		local status
		status=$(echo "$response" | jq -r '.status // empty')
		if [[ "$status" == "ok" ]]; then
			html=$(echo "$response" | jq -r '.solution.response // empty')
			export FS_COOKIES
			FS_COOKIES=$(echo "$response" | jq -r '[.solution.cookies[] | .name + "=" + .value] | join("; ")')
			user_agent=$(echo "$response" | jq -r '.solution.userAgent // empty')
			return 0
		fi
		yellow_log "[!] FlareSolverr attempt $attempt/$max_retries failed: $url"
		sleep 5
	done
	red_log "[-] FlareSolverr failed after $max_retries attempts: $url"
	return 1
}

_cfb_get() {
	local url=$1
	local max_retries=3
	local attempt

	for attempt in $(seq 1 $max_retries); do
		local response_file
		rm -f /tmp/cfb_response_headers.txt
		response_file=$(mktemp)
		local http_code
		http_code=$(curl -s -o "$response_file" -w '%{http_code}' \
			-D /tmp/cfb_response_headers.txt \
			-G --data-urlencode "url=$url" \
			--max-time 120 \
			"http://localhost:8000/html")
		if [[ "$http_code" == "200" ]]; then
			html=$(cat "$response_file")
			if [[ -n "$html" ]]; then
				export FS_COOKIES
				FS_COOKIES=$(grep -i '^x-cf-bypasser-cookies:' /tmp/cfb_response_headers.txt 2>/dev/null | cut -d':' -f2- | xargs)
				local cfb_ua
				cfb_ua=$(grep -i '^x-cf-bypasser-user-agent:' /tmp/cfb_response_headers.txt 2>/dev/null | cut -d':' -f2- | xargs)
				[[ -n "$cfb_ua" ]] && user_agent="$cfb_ua"
				rm -f "$response_file" /tmp/cfb_response_headers.txt
				return 0
			fi
		else
			yellow_log "[!] CFB attempt $attempt/$max_retries: HTTP $http_code: $url"
		fi
	done
	return 1
}

_FFS_FAILED=0

_cf_get() {
	if [[ "$_FFS_FAILED" -eq 0 ]]; then
		_fs_get "$@" && return 0
		yellow_log "[!] FlareSolverr failed, falling back to CFB"
		_FFS_FAILED=1
	fi
	_cfb_get "$@"
}

get_apkmirror_version_code() {
	local pkg_name=$1
	local arch=${2:-arm64-v8a}
	local dpi=${3:-nodpi}
	local version_code=""

	# Primary method: Query official APKMirror API endpoint (fast, bypasses Cloudflare)
	local api_res
	api_res=$(curl -s --connect-timeout 10 --max-time 15 -X POST 'https://www.apkmirror.com/wp-json/apkm/v1/app_exists/' \
		-H 'Authorization: Basic YXBpLWFwa3VwZGF0ZXI6cm01cmNmcnVVakt5MDRzTXB5TVBKWFc4' \
		-H 'Content-Type: application/json' \
		-H 'User-Agent: APKUpdater-v3.0.3' \
		-d "{\"pnames\":[\"$pkg_name\"],\"exclude\":[\"alpha\",\"beta\"]}" 2>/dev/null)

	if [[ -n "$api_res" ]]; then
		version_code=$(echo "$api_res" | jq -r --arg pkg "$pkg_name" --arg arch "$arch" --arg dpi "$dpi" '
			.data[]? | select(.pname == $pkg) |
			(
				([.apks[]? | select((.arches[]? == $arch) and (.dpis[]? == $dpi)) | .version_code | tonumber] | max) //
				([.apks[]? | select(.arches[]? == $arch) | .version_code | tonumber] | max) //
				([.apks[]?.version_code | tonumber] | max)
			) // empty
		' 2>/dev/null)
	fi

	# Fallback: if API did not return version code, scrape release page from APKMirror
	if [[ -z "$version_code" ]]; then
		local apps_json="./src/build/helper/apps.json"
		local list_url
		list_url=$(jq -r --arg pkg "$pkg_name" '.apkmirror[$pkg].list_url // empty' "$apps_json")
		if [[ -n "$list_url" ]]; then
			_cf_get "$list_url" 2>/dev/null || true
			local version_href
			version_href=$(echo "$html" | $pup 'h5.appRowTitle a.fontBlack json{}' 2>/dev/null | \
				jq -r '.[] | select(.text | test("(?i)beta|alpha") | not) | .href' 2>/dev/null | head -1)
			[[ -z "$version_href" ]] && \
				version_href=$(echo "$html" | $pup 'h5.appRowTitle a.fontBlack attr{href}' 2>/dev/null | head -1)

			if [[ -n "$version_href" ]]; then
				_cf_get "https://www.apkmirror.com$version_href" 2>/dev/null || true
				local vtable_html rows
				vtable_html=$(echo "$html" | $pup 'div.variants-table' 2>/dev/null)
				rows=$(echo "$vtable_html" | tr '\n' ' ' | sed 's/<div class="table-row/\n<div class="table-row/g')
				version_code=$(echo "$rows" | grep -i "$arch" | grep -oP '\b\d{8,10}\b' | head -1)
				[[ -z "$version_code" ]] && version_code=$(echo "$rows" | grep -oP '\b\d{8,10}\b' | head -1)
			fi
		fi
	fi

	printf '%s' "$version_code"
}

get_apk() {
	local pkg_name=$1 apk_name=$2
	local pkg_type=${3:-apk} arch=${4:-} dpi=${5:-} minver=${6:-}
	local target_version_code="${7:-$target_version_code}"
	local base_url="https://www.apkmirror.com"
	local html=""

	local apps_json="./src/build/helper/apps.json"
	local list_url example_url
	list_url=$(jq -r --arg pkg "$pkg_name" '.apkmirror[$pkg].list_url // empty' "$apps_json")
	example_url=$(jq -r --arg pkg "$pkg_name" '.apkmirror[$pkg].example_url // empty' "$apps_json")

	if [[ -z "$list_url" ]]; then
		red_log "[-] Package $pkg_name not found in apps.json"
		return 1
	fi

	local base_apk
	if [[ "$pkg_type" == "bundle" ]] || [[ "$pkg_type" == "bundle_extract" ]]; then
		base_apk="$apk_name.apkm"
	else
		base_apk="$apk_name.apk"
	fi

	detect_version "$pkg_name"
	version=$(printf '%s\n' "$version" "$prefer_version" | sort -V | tail -n1)
	unset prefer_version
	export version

	green_log "[+] Detected version: ${version:-latest} [$pkg_name]"
	local vcode_log=""
	[[ -n "$target_version_code" ]] && vcode_log=" vcode=$target_version_code"
	[[ -n "$target_version_codes" ]] && vcode_log=" vcodes=[$target_version_codes]"
	green_log "[+] Downloading $apk_name (type=$pkg_type arch=${arch:-any} dpi=$dpi$vcode_log)"

	local version_href=""

	if [[ -n "$example_url" && -n "$version" ]]; then
		version_href="${example_url#$base_url}"
		local slug_ver
		slug_ver=$(echo "$version_href" | grep -oP '\d+(-\d+)+' | tail -1)
		[[ -z "$slug_ver" ]] && slug_ver=$(echo "$version_href" | grep -oP '\d+(-\d+)*' | tail -1)
		local target_ver
		target_ver=$(echo "$version" | tr '.' '-' | tr -d '+' | grep -oP '\d+(-\d+)+' | tail -1)
		[[ -z "$target_ver" ]] && target_ver=$(echo "$version" | tr '.' '-' | tr -d '+' | grep -oP '\d+(-\d+)*' | tail -1)
		if [[ -n "$slug_ver" && -n "$target_ver" ]]; then
			version_href="${version_href/$slug_ver/$target_ver}"
		fi
	else
		_cf_get "$list_url" || return 1

		version_href=$(echo "$html" | $pup 'h5.appRowTitle a.fontBlack json{}' | \
			jq -r '.[] | select(.text | test("(?i)beta|alpha") | not) | .href' | head -1)
		[[ -z "$version_href" ]] && \
			version_href=$(echo "$html" | $pup 'h5.appRowTitle a.fontBlack attr{href}' | head -1)

		if [[ -z "$version_href" ]]; then
			red_log "[-] Could not find release on APKMirror"
			return 1
		fi

		if [[ -n "$version" ]]; then
			local slug_ver
			slug_ver=$(echo "$version_href" | grep -oP '\d+(-\d+)+' | tail -1)
			[[ -z "$slug_ver" ]] && slug_ver=$(echo "$version_href" | grep -oP '\d+(-\d+)*' | tail -1)
			local target_ver
			target_ver=$(echo "$version" | tr '.' '-' | tr -d '+' | grep -oP '\d+(-\d+)+' | tail -1)
			[[ -z "$target_ver" ]] && target_ver=$(echo "$version" | tr '.' '-' | tr -d '+' | grep -oP '\d+(-\d+)*' | tail -1)
			if [[ -n "$slug_ver" && -n "$target_ver" ]]; then
				version_href="${version_href/$slug_ver/$target_ver}"
			fi
		fi
	fi

	echo "$base_url$version_href"

	_cf_get "$base_url$version_href" || return 1

	if [[ "$html" == *"Page Not Found"* ]] || [[ "$html" == *"404 Whoops"* ]]; then
		yellow_log "[!] Version page not found, searching uploads pages..."
		local target_ver_dot="$version"
		version_href=""
		for page_num in $(seq 1 10); do
			local page_url="$list_url"
			if [[ $page_num -gt 1 ]]; then
				page_url="${list_url%%\?*}/page/$page_num/?${list_url#*\?}"
			fi
			_cf_get "$page_url" || return 1
			if [[ -n "$target_ver_dot" ]]; then
				version_href=$(echo "$html" | $pup 'h5.appRowTitle a.fontBlack json{}' | \
					jq -r --arg v "$target_ver_dot" '.[] | select(.text | contains($v)) | .href' | head -1)
			else
				version_href=$(echo "$html" | $pup 'h5.appRowTitle a.fontBlack json{}' | \
					jq -r '.[] | select(.text | test("(?i)beta|alpha") | not) | .href' | head -1)
			fi
			[[ -n "$version_href" ]] && break
		done
		if [[ -z "$version_href" ]]; then
			red_log "[-] Could not find version on APKMirror"
			return 1
		fi
		echo "$base_url$version_href"
		_cf_get "$base_url$version_href" || return 1
	fi

	# If compatible version lookup was empty, derive app version from selected release URL slug.
	if [[ -z "$version" ]]; then
		version_slug=$(echo "$version_href" | grep -oP '\d+(-\d+)+' | tail -1)
		[[ -z "$version_slug" ]] && version_slug=$(echo "$version_href" | grep -oP '\d+(-\d+)*' | tail -1)
		if [[ -n "$version_slug" ]]; then
			version=${version_slug//-/.}
		fi
	fi

	export version
	export_app_version "$version"

	local type_badge="APK"
	[[ "$pkg_type" == "bundle" || "$pkg_type" == "bundle_extract" ]] && type_badge="BUNDLE"

	local vtable_html rows variant_href=""
	vtable_html=$(echo "$html" | $pup 'div.variants-table')
	rows=$(echo "$vtable_html" | tr '\n' ' ' | sed 's/<div class="table-row/\n<div class="table-row/g')

	local dpi_fallback=()
	[[ -n "$dpi" ]] && dpi_fallback+=("$dpi")
	dpi_fallback+=("480-640dpi" "640dpi" "320-640dpi" "160-640dpi" "120-640dpi" "120-480dpi" "320-480dpi" "480dpi" "nodpi" "")

	local arch_attempts=("$arch")
	[[ -n "$arch" && "$arch" != "universal" ]] && arch_attempts+=("universal" "")

	local minver_attempts=("$minver")
	[[ -n "$minver" ]] && minver_attempts+=("")

	local type_attempts=("$type_badge")
	if [[ "$type_badge" == "BUNDLE" ]]; then
		type_attempts+=("APK")
	else
		type_attempts+=("BUNDLE")
	fi

	local matched_type=""
	for try_type in "${type_attempts[@]}"; do
		for try_arch in "${arch_attempts[@]}"; do
			for try_minver in "${minver_attempts[@]}"; do
				local candidate_rows
				candidate_rows=$(echo "$rows" | grep -iP "apkm-badge[^>]*>\s*$try_type\s*<")
				[[ -n "$try_arch" ]] && candidate_rows=$(echo "$candidate_rows" | grep -i "$try_arch")
				[[ -n "$try_minver" ]] && candidate_rows=$(echo "$candidate_rows" | grep -i "$try_minver")
				if [[ -n "$target_version_codes" ]]; then
					local vcode_pattern
					vcode_pattern=$(echo "$target_version_codes" | tr ' ' '|')
					local vcode_rows
					vcode_rows=$(echo "$candidate_rows" | grep -E "$vcode_pattern")
					if [[ -n "$vcode_rows" ]]; then
						candidate_rows="$vcode_rows"
					else
						yellow_log "[!] None of target version codes ($target_version_codes) found in candidates, trying without version code filter"
					fi
				elif [[ -n "$target_version_code" ]]; then
					local vcode_rows
					vcode_rows=$(echo "$candidate_rows" | grep -F "$target_version_code")
					if [[ -n "$vcode_rows" ]]; then
						candidate_rows="$vcode_rows"
					else
						yellow_log "[!] Target version code $target_version_code not found in candidates, trying without version code filter"
					fi
				fi

				if [[ -z "$candidate_rows" ]]; then
					continue
				fi

				for fb_dpi in "${dpi_fallback[@]}"; do
					local dpi_filtered
					if [[ -n "$fb_dpi" ]]; then
						dpi_filtered=$(echo "$candidate_rows" | grep -i "$fb_dpi")
					else
						dpi_filtered="$candidate_rows"
					fi

					variant_href=$(echo "$dpi_filtered" | grep -oP 'accent_color[^>]*href="\K[^"]+' | head -1)
					if [[ -n "$variant_href" ]]; then
						matched_type="$try_type"
						[[ "$try_type" != "$type_badge" ]] && yellow_log "[!] Type fallback: $type_badge -> $try_type"
						[[ "$try_arch" != "$arch" ]] && yellow_log "[!] Arch fallback: ${arch:-any} -> ${try_arch:-any}"
						[[ "$try_minver" != "$minver" ]] && yellow_log "[!] MinVer fallback: ${minver:-any} -> ${try_minver:-any}"
						[[ -n "$dpi" && "$fb_dpi" != "$dpi" ]] && yellow_log "[!] DPI fallback: ${dpi} -> ${fb_dpi:-any}"
						break 4
					fi
				done
			done
		done
	done

	if [[ -z "$variant_href" ]]; then
		red_log "[-] Could not find variant (type=$type_badge arch=${arch:-any} dpi=$dpi)"
		return 1
	fi
	variant_href=$(echo "$variant_href" | sed 's/&amp;/\&/g')
	echo "$base_url$variant_href"

	if [[ "$matched_type" == "BUNDLE" ]]; then
		base_apk="$apk_name.apkm"
	else
		base_apk="$apk_name.apk"
	fi

	_cf_get "$base_url$variant_href" || return 1

	local dl_btn_href
	local all_dl_btns
	all_dl_btns=$(echo "$html" | $pup 'a.downloadButton attr{href}')
	if [[ "$matched_type" == "BUNDLE" ]]; then
		dl_btn_href=$(echo "$all_dl_btns" | grep -v 'forcebaseapk' | head -1)
		[[ -z "$dl_btn_href" ]] && dl_btn_href=$(echo "$all_dl_btns" | head -1)
	else
		dl_btn_href=$(echo "$all_dl_btns" | grep 'forcebaseapk' | head -1)
		[[ -z "$dl_btn_href" ]] && dl_btn_href=$(echo "$all_dl_btns" | head -1)
	fi

	if [[ -z "$dl_btn_href" ]]; then
		red_log "[-] Could not find download button"
		return 1
	fi
	dl_btn_href=$(echo "$dl_btn_href" | sed 's/&amp;/\&/g')

	_cf_get "$base_url$dl_btn_href" || return 1

	local final_href
	final_href=$(echo "$html" | $pup 'a#download-link attr{href}' | head -1)
	[[ -z "$final_href" ]] && \
		final_href=$(echo "$html" | grep -oP 'id="download-link"[^>]*href="\K[^"]+' | head -1)

	if [[ -z "$final_href" ]]; then
		red_log "[-] Could not find final download link"
		return 1
	fi
	final_href=$(echo "$final_href" | sed 's/&amp;/\&/g')

	echo "$base_url$final_href"
	local cookie_args=()
	[[ -n "$FS_COOKIES" ]] && cookie_args=(--header "Cookie: $FS_COOKIES")
	wget -nv -O "./download/$base_apk" \
		--header="User-Agent: $user_agent" \
		--referer="$base_url$dl_btn_href" \
		"${cookie_args[@]}" \
		--timeout=120 \
		"$base_url$final_href" || rm -f "./download/$base_apk"

	if [[ -s "./download/$base_apk" ]]; then
		green_log "[+] Successfully downloaded $apk_name"
	else
		red_log "[-] Failed to download $apk_name"
		return 1
	fi

	if [[ "$matched_type" == "BUNDLE" ]]; then
		if [[ "$pkg_type" == "bundle_extract" && "$type_badge" == "BUNDLE" ]]; then
			unzip "./download/$base_apk" -d "./download/$(basename "$base_apk" .apkm)" > /dev/null 2>&1
		else
			green_log "[+] Merge splits apk to standalone apk"
			java -jar $APKEditor m -i "./download/$apk_name.apkm" -o "./download/$apk_name.apk" > /dev/null 2>&1
		fi
	fi
	unset target_version_code
	unset target_version_codes
}

get_apkpure() {
	local pkg_name=$1 apk_name=$2 pkg_type=${3:-apk}
	local html=""

	local apps_json="./src/build/helper/apps.json"
	local base_download_url
	base_download_url=$(jq -r --arg pkg "$pkg_name" '.apkpure[$pkg].download_url // empty' "$apps_json")

	if [[ -z "$base_download_url" ]]; then
		red_log "[-] Package $pkg_name not found in apps.json (apkpure)"
		return 1
	fi

	detect_version "$pkg_name"
	version=$(printf '%s\n' "$version" "$prefer_version" | sort -V | tail -n1)
	unset prefer_version
	export version

	if [[ "$pkg_type" == "bundle" ]] || [[ "$pkg_type" == "bundle_extract" ]]; then
		local base_apk="$apk_name.xapk"
	else
		local base_apk="$apk_name.apk"
	fi

	local dl_page_url
	if [[ -n "$version" ]]; then
		dl_page_url="${base_download_url%/}/$version"
	else
		dl_page_url="$base_download_url"
	fi

	green_log "[+] Downloading $apk_name from APKPure (type=$pkg_type)"
	echo "$dl_page_url"

	_cf_get "$dl_page_url" || return 1

	if [[ -z "$version" ]]; then
		version=$(echo "$html" | $pup 'h2 text{}' | grep -oP '\d+(\.\d+)+' | head -1)
	fi
	green_log "[+] Version: $version"
	export_app_version "$version"

	local download_url
	download_url=$(echo "$html" | $pup 'a#download_link attr{href}' | head -1)
	[[ -z "$download_url" ]] && \
		download_url=$(echo "$html" | grep -oP '<a[^>]+id="download_link"[^>]+href="\Khttps://[^"]+' | head -1)

	if [[ -z "$download_url" ]]; then
		red_log "[-] Could not find download link on APKPure"
		return 1
	fi
	echo "$download_url"

	local cookie_args=()
	[[ -n "$FS_COOKIES" ]] && cookie_args=(--header "Cookie: $FS_COOKIES")
	wget -nv -O "./download/$base_apk" \
		--header="User-Agent: $user_agent" \
		--referer="$dl_page_url" \
		"${cookie_args[@]}" \
		--timeout=120 \
		"$download_url"

	if [[ -f "./download/$base_apk" ]]; then
		green_log "[+] Successfully downloaded $apk_name"
	else
		red_log "[-] Failed to download $apk_name"
		return 1
	fi
	if [[ "$pkg_type" == "bundle" ]]; then
		if unzip -l "./download/$base_apk" 2>/dev/null | grep -q '\.apk$'; then
			green_log "[+] Merge splits apk to standalone apk"
			if ! java -jar $APKEditor m -i "./download/$apk_name.xapk" -o "./download/$apk_name.apk" > /dev/null 2>&1; then
				red_log "[-] Failed to merge $apk_name.xapk to standalone apk"
				return 1
			fi
		elif unzip -l "./download/$base_apk" 2>/dev/null | grep -q 'AndroidManifest.xml'; then
			green_log "[+] File is already a standalone APK, renaming"
			mv "./download/$base_apk" "./download/$apk_name.apk"
		else
			red_log "[-] Unknown file format for $base_apk"
			return 1
		fi
	elif [[ "$pkg_type" == "bundle_extract" ]]; then
		unzip "./download/$base_apk" -d "./download/$(basename "$base_apk" .xapk)" > /dev/null 2>&1
	fi
}

# Download APK from Uptodown (bypasses Uptodown App Store wrapper using -x endpoint)
get_apk_uptodown() {
	local pkg_name=$1 apk_name=$2 pkg_type=${3:-apk}
	local html=""

	local apps_json="./src/build/helper/apps.json"
	local helper_script="./src/build/helper/uptodown_dl/uptodown_dl.py"
	local base_url=""

	if [[ -f "$apps_json" ]]; then
		base_url=$(jq -r --arg pkg "$pkg_name" '.uptodown[$pkg].url // empty' "$apps_json" 2>/dev/null)
	fi

	detect_version "$pkg_name"
	version=$(printf '%s\n' "$version" "$prefer_version" | sort -V | tail -n1)
	unset prefer_version
	export version

	green_log "[+] Downloading $apk_name from Uptodown [$pkg_name] (type=$pkg_type target_ver=${version:-latest})"

	local base_apk="$apk_name.apk"
	local is_split=false
	local downloaded=false

	# 1. Try via Python helper (curl_cffi / requests with slug generator adapted from Morphe-AutoBuilds)
	if [[ -f "$helper_script" ]]; then
		local py_args=("$pkg_name" "./download/$base_apk" "--pkg-type" "$pkg_type")
		[[ -n "$version" ]] && py_args+=("--version" "$version")
		[[ -n "$base_url" ]] && py_args+=("--url" "$base_url")

		local result exit_code
		result=$(python3 "$helper_script" "${py_args[@]}" 2>&1)
		exit_code=$?

		local json_result
		json_result=$(echo "$result" | grep -E '^\{.*\}$' | tail -1)
		[[ -z "$json_result" ]] && json_result=$(echo "$result" | grep '^{' | tail -1)

		if [[ $exit_code -eq 0 && -n "$json_result" ]]; then
			local success
			success=$(echo "$json_result" | jq -r '.success // false' 2>/dev/null)
			if [[ "$success" == "true" ]]; then
				local dl_size
				dl_size=$(echo "$json_result" | jq -r '.size // 0' 2>/dev/null)
				is_split=$(echo "$json_result" | jq -r '.isSplit // false' 2>/dev/null)
				local version_name
				version_name=$(echo "$json_result" | jq -r '.versionName // empty' 2>/dev/null)
				if [[ -n "$version_name" ]]; then
					version="$version_name"
					export version
					export_app_version "$version"
				fi
				green_log "[+] Downloaded $apk_name via Uptodown helper (${dl_size} bytes)"
				downloaded=true
			fi
		fi
	fi

	# 2. Fallback to FlareSolverr / CFB shell scraping pipeline if helper failed
	if [[ "$downloaded" == "false" ]]; then
		if [[ -z "$base_url" ]]; then
			# Generate candidate URL from package name or app slug
			local slug="${pkg_name#com.}"
			slug="${slug#google.android.}"
			slug="${slug#android.}"
			slug="${slug//./-}"
			base_url="https://${slug}.en.uptodown.com/android"
		fi
		base_url="${base_url%/}"

		_cf_get "$base_url/versions" || return 1

		local data_code
		data_code=$(echo "$html" | grep -oP 'id="detail-app-name"[^>]*data-code="\K\d+' | head -1)
		[[ -z "$data_code" ]] && data_code=$(echo "$html" | grep -oP 'data-code="\K\d+(?="[^>]*id="detail-app-name")' | head -1)

		local version_url="" kind_file="apk"
		if [[ -n "$data_code" ]]; then
			local api_resp
			api_resp=$(wget -qO- --header="User-Agent: $user_agent" "$base_url/apps/$data_code/versions/1" 2>/dev/null)
			if [[ -n "$api_resp" ]]; then
				if [[ -n "$version" ]]; then
					version_url=$(echo "$api_resp" | jq -r --arg v "$version" '.data[] | select(.version == $v) | "\(.versionURL.url)/\(.versionURL.extraURL)/\(.versionURL.versionID)"' | head -1)
					kind_file=$(echo "$api_resp" | jq -r --arg v "$version" '.data[] | select(.version == $v) | .kindFile' | head -1)
				fi
				if [[ -z "$version_url" ]]; then
					version_url=$(echo "$api_resp" | jq -r '.data[0] | "\(.versionURL.url)/\(.versionURL.extraURL)/\(.versionURL.versionID)"' | head -1)
					kind_file=$(echo "$api_resp" | jq -r '.data[0].kindFile // "apk"' | head -1)
					version=$(echo "$api_resp" | jq -r '.data[0].version' | head -1)
				fi
			fi
		fi

		[[ -z "$version_url" ]] && version_url="$base_url/download"

		# Apply the -x bypass for XAPKs / version pages to avoid the Uptodown App Store wrapper
		if [[ "$kind_file" == "xapk" || "$version_url" =~ /download/[0-9]+$ ]]; then
			version_url="${version_url}-x"
			is_split=true
		fi

		green_log "[+] Target Uptodown download page: $version_url"
		_cf_get "$version_url" || return 1

		if [[ -z "$version" ]]; then
			version=$(echo "$html" | grep -oP 'class="version">\K[^<]+' | head -1)
		fi
		export_app_version "$version"

		local download_url
		download_url=$(echo "$html" | grep -oP 'https://dw\.uptodown\.com/dwn/[^"'\''\s<>]+' | head -1)
		if [[ -z "$download_url" ]]; then
			local data_url
			data_url=$(echo "$html" | grep -oP 'id="detail-download-button"[^>]*data-url="\K[^"]+' | head -1)
			[[ -n "$data_url" ]] && download_url="https://dw.uptodown.com/dwn/$data_url"
		fi

		if [[ -z "$download_url" ]]; then
			red_log "[-] Could not extract direct download URL from Uptodown"
			return 1
		fi

		local cookie_args=()
		[[ -n "$FS_COOKIES" ]] && cookie_args=(--header "Cookie: $FS_COOKIES")

		wget -nv -O "./download/$base_apk" \
			--header="User-Agent: $user_agent" \
			--referer="$version_url" \
			"${cookie_args[@]}" \
			--timeout=120 \
			"$download_url"

		if [[ ! -f "./download/$base_apk" ]]; then
			red_log "[-] Failed to download $apk_name from Uptodown"
			return 1
		fi
	fi

	# 3. Handle XAPK / Split APK bundles merging
	if [[ "$is_split" == "true" || "$pkg_type" == "bundle" || "$pkg_type" == "bundle_extract" ]]; then
		if unzip -l "./download/$base_apk" 2>/dev/null | grep -q '\.apk$'; then
			if [[ "$pkg_type" == "bundle_extract" ]]; then
				unzip "./download/$base_apk" -d "./download/$apk_name" > /dev/null 2>&1
			else
				green_log "[+] Merge splits apk to standalone apk"
				java -jar $APKEditor m -i "./download/$base_apk" -o "./download/$apk_name.apk.merged" > /dev/null 2>&1
				if [[ -f "./download/$apk_name.apk.merged" ]]; then
					mv "./download/$apk_name.apk.merged" "./download/$apk_name.apk"
				fi
			fi
		fi
	fi

	if [[ ! -f "./download/$apk_name.apk" && ! -f "./download/$base_apk" ]]; then
		red_log "[-] Failed to obtain $apk_name from Uptodown"
		return 1
	fi

	green_log "[+] Successfully obtained $apk_name from Uptodown"
}

# Download APK from Google Play Store via AuroraStore anonymous auth
get_apk_chplay() {
	local pkg_name=$1 apk_name=$2
	local pkg_type=${3:-apk} dispenser_url=${4:-}

	local helper_script="./src/build/helper/ggplay_dl/ggplay_dl.py"

	green_log "[+] Downloading $apk_name from Google Play (Ch Play) [$pkg_name]"

	local dispenser_arg=""
	[[ -n "$dispenser_url" ]] && dispenser_arg="--dispenser $dispenser_url"

	local result
	result=$(python "$helper_script" "$pkg_name" "./download/$apk_name.apk" $dispenser_arg 2>&1)
	local exit_code=$?

	local logs
	logs=$(echo "$result" | grep -v '^{' | grep -v '^}')
	local json_result
	json_result=$(echo "$result" | grep '^{')

	if [[ $exit_code -ne 0 ]]; then
		red_log "[-] Failed to download $apk_name from Google Play"
		[[ -n "$logs" ]] && echo "$logs" >&2
		return 1
	fi

	local success
	success=$(echo "$json_result" | jq -r '.success // false' 2>/dev/null)
	if [[ "$success" != "true" ]]; then
		local error_msg
		error_msg=$(echo "$json_result" | jq -r '.error // "Unknown error"' 2>/dev/null)
		red_log "[-] Download failed: $error_msg"
		return 1
	fi

	local dl_size
	dl_size=$(echo "$json_result" | jq -r '.size // 0' 2>/dev/null)
	local is_split
	is_split=$(echo "$json_result" | jq -r '.isSplit // false' 2>/dev/null)
	local version_name
	version_name=$(echo "$json_result" | jq -r '.versionName // empty' 2>/dev/null)

	if [[ -n "$version_name" ]]; then
		version="$version_name"
		export version
		export_app_version "$version"
	fi

	green_log "[+] Successfully downloaded $apk_name (${dl_size} bytes)"

	if [[ "$is_split" == "true" ]]; then
		if [[ "$pkg_type" == "bundle_extract" ]]; then
			green_log "[+] Extracting split APKs"
			unzip "./download/$apk_name.apk" -d "./download/$apk_name" > /dev/null 2>&1
		else
			green_log "[+] Merging split APKs to standalone apk"
			java -jar $APKEditor m -i "./download/$apk_name.apk" -o "./download/$apk_name.apk.merged" > /dev/null 2>&1
			if [[ -f "./download/$apk_name.apk.merged" ]]; then
				mv "./download/$apk_name.apk.merged" "./download/$apk_name.apk"
			fi
		fi
	fi
}

#################################################

# Patching apps with CLI:
patch() {
	green_log "[+] Patching $1:"
	if [ -f "./download/$1.apk" ]; then
		echo "Patching with Morphe"
		if ! ls morphe-desktop-*.jar >/dev/null 2>&1; then
			red_log "[-] morphe-desktop-*.jar not found"
			exit 1
		fi
		unset CI GITHUB_ACTION GITHUB_ACTIONS GITHUB_ACTOR GITHUB_ENV GITHUB_EVENT_NAME GITHUB_EVENT_PATH GITHUB_HEAD_REF GITHUB_JOB GITHUB_REF GITHUB_REPOSITORY GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_SHA GITHUB_WORKFLOW GITHUB_WORKSPACE RUN_ID RUN_NUMBER
		if ! eval java -jar morphe-desktop-*.jar patch $(morphe_patches_args "-p") --options-file ./src/options/$2.json --out=./release/$1-$2.apk$excludePatches$includePatches --keystore=./src/morphe.keystore --force --continue-on-error ./download/$1.apk; then
			red_log "[-] Morphe patching failed for $1"
			exit 1
		fi
		if ! ls ./release/$1-$2*.apk >/dev/null 2>&1; then
			red_log "[-] Output APK not found in ./release/ for $1"
			exit 1
		fi
		unset version
		unset lock_version
		unset excludePatches
		unset includePatches
		unset morpheExcludePatches
		unset morpheIncludePatches
		unset communityExcludePatches
		unset communityIncludePatches
		unset APP_VERSION
		unset target_version_code
		unset target_version_codes
	else
		red_log "[-] Not found $1.apk"
		exit 1
	fi
}

#################################################

morphe_disable_play_store_updates() {
	local input_apk="./release/$1-$2.apk"
	local output_apk="./release/$1-$2-detached.apk"
	local patches_args
	patches_args="$(morphe_patches_args "-p" "morphe-universal-*.mpp.disabled")"

	if [ -z "$patches_args" ]; then
		red_log "[-] Morphe universal patches bundle not found"
		exit 1
	fi

	green_log "[+] Disabling Play Store updates for $1:"
	if eval java -jar morphe-desktop-*.jar patch $patches_args --exclusive -e "\"Disable Play Store updates\"" \
		--out="$output_apk" --keystore=./src/morphe.keystore --force "$input_apk"; then
		mv "$output_apk" "$input_apk"
	else
		red_log "[-] Failed to disable Play Store updates for $1"
		exit 1
	fi
}

lspatch() {
	green_log "[+] Patching $1:"
	if [ -f "./download/$1.apk" ]; then
		local module
		if [[ "$2" == *.apk ]]; then
			local -a matches=($2)
			module="${matches[0]}"
		else
			module="$2.apk"
		fi
		if [[ ! -f "$module" ]]; then
			red_log "[-] Module not found: $2"
			return 1
		fi
		if ! java -jar lspatch-*-release.jar ./download/$1.apk -k ./src/lspatch-signing.p12 "morphe" "fiorenmas" "morphe" $4 -m "$module" -o ./release/; then
			red_log "[-] LSPatch failed for $1"
			exit 1
		fi
		mv ./release/$1-*-lspatched.apk ./release/$1-$3.apk
		unset version
		unset lock_version
	else
		red_log "[-] Not found $1.apk"
		exit 1
	fi
}

npatch() {
	green_log "[+] Patching $1:"
	if [ -f "./download/$1.apk" ]; then
		local module
		if [[ "$2" == *.apk ]]; then
			local -a matches=($2)
			module="${matches[0]}"
		else
			module="$2.apk"
		fi
		if [[ ! -f "$module" ]]; then
			red_log "[-] Module not found: $2"
			return 1
		fi
		if ! java -jar jar*.jar ./download/$1.apk -k ./src/fiorenmas.ks "fiorenmas" "morphe" "fiorenmas" $4 -m "$module" -o ./release/; then
			red_log "[-] NPatch failed for $1"
			exit 1
		fi
		mv ./release/$1-*-npatched.apk ./release/$1-$3.apk
		unset version
		unset lock_version
	else
		red_log "[-] Not found $1.apk"
		exit 1
	fi
}
#################################################

split_editor() {
    if [[ -z "$3" || -z "$4" ]]; then
        green_log "[+] Merge splits apk to standalone apk"
        java -jar $APKEditor m -i "./download/$1" -o "./download/$1.apk" > /dev/null 2>&1
        return 0
    fi
    IFS=' ' read -r -a include_files <<< "$4"
    mkdir -p "./download/$2"
    for file in "./download/$1"/*.apk; do
        filename=$(basename "$file")
        basename_no_ext="${filename%.apk}"
        if [[ "$filename" == "base.apk" ]]; then
            cp -f "$file" "./download/$2/" > /dev/null 2>&1
            continue
        fi
        if [[ "$3" == "include" ]]; then
            if [[ " ${include_files[*]} " =~ " ${basename_no_ext} " ]]; then
                cp -f "$file" "./download/$2/" > /dev/null 2>&1
            fi
        elif [[ "$3" == "exclude" ]]; then
            if [[ ! " ${include_files[*]} " =~ " ${basename_no_ext} " ]]; then
                cp -f "$file" "./download/$2/" > /dev/null 2>&1
            fi
        fi
    done

    green_log "[+] Merge splits apk to standalone apk"
    java -jar $APKEditor m -i ./download/$2 -o ./download/$2.apk > /dev/null 2>&1
}

#################################################

archs=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
libs=("armeabi-v7a x86_64 x86" "arm64-v8a x86_64 x86" "armeabi-v7a arm64-v8a x86" "armeabi-v7a arm64-v8a x86_64")

# Remove unused architectures directly
apk_editor() {
	local apk="$1" keep="$2"; shift 2
	local dir="./download/$apk"
	rm -rf "$dir" && unzip -q "./download/$apk.apk" -d "$dir" || return 1
	for r in "$@"; do rm -rf "$dir/lib/$r"; done
	(cd "$dir" && zip -qr "../$apk-$keep.apk" .)
}

# Split architectures using Morphe cli
split_arch() {
	green_log "[+] Splitting $1 to ${archs[i]}:"
	if [ -f "./download/$1.apk" ]; then
		get_patches_key "$1-$2"
		eval java -jar morphe-desktop-*.jar patch \
		$(morphe_patches_args "-p") --options-file ./src/options/$2.json \
		--striplibs ${archs[i]} \
		--keystore=./src/morphe.keystore --force \
		--out=./release/$1-${archs[i]}-$2.apk$excludePatches$includePatches \
		./download/$1.apk
		unset version
		unset lock_version
		unset excludePatches
		unset includePatches
		unset morpheExcludePatches
		unset morpheIncludePatches
		unset communityExcludePatches
		unset communityIncludePatches
	else
		red_log "[-] Not found $1.apk"
		exit 1
	fi
}

#################################################