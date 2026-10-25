#!/bin/bash

LAST_FETCHED_REPO=""
CACHED_RELEASES_JSON=""
OWN_REPO_CACHE_FILE="/tmp/ci_own_releases.json"

# Check new patch:
get_date() {
	local json
	local ur_repo="${repository:-$GITHUB_REPOSITORY}"
	if [ "$1" = "$LAST_FETCHED_REPO" ] && [ -n "$CACHED_RELEASES_JSON" ]; then
		json="$CACHED_RELEASES_JSON"
	elif [ -n "$ur_repo" ] && [ "$1" = "$ur_repo" ] && [ -s "$OWN_REPO_CACHE_FILE" ]; then
		json=$(cat "$OWN_REPO_CACHE_FILE")
		LAST_FETCHED_REPO="$1"
		CACHED_RELEASES_JSON="$json"
	else
		if command -v wget >/dev/null 2>&1; then
			local auth_header=()
			if [ -n "$GITHUB_TOKEN" ]; then
				auth_header=(--header="Authorization: Bearer $GITHUB_TOKEN")
			fi
			json=$(wget -qO- "${auth_header[@]}" "https://api.github.com/repos/$1/releases?per_page=100")
		else
			local auth_header=()
			if [ -n "$GITHUB_TOKEN" ]; then
				auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")
			fi
			json=$(curl -s "${auth_header[@]}" "https://api.github.com/repos/$1/releases?per_page=100")
		fi
		LAST_FETCHED_REPO="$1"
		CACHED_RELEASES_JSON="$json"
		if [ -n "$ur_repo" ] && [ "$1" = "$ur_repo" ] && [ -n "$json" ]; then
			printf '%s' "$json" > "$OWN_REPO_CACHE_FILE"
		fi
	fi
	case "$2" in
		latest)
			updated_at=$(echo "$json" | jq --arg pat "$3" -r 'first(.[] | select(.prerelease == false) | .assets[] | select(.name | test($pat)) | .updated_at)')
			;;
		prerelease)
			updated_at=$(echo "$json" | jq --arg pat "$3" -r 'first(.[] | select(.prerelease == true) | .assets[] | select(.name | test($pat)) | .updated_at)')
			;;
		all)
			updated_at=$(echo "$json" | jq --arg pat "$3" -r 'first(.[] | .assets[] | select(.name | test($pat)) | .updated_at)')
			;;
		*)
			updated_at=$(echo "$json" | jq --arg pat "$3" --arg tag "$2" -r 'first(.[] | select(.tag_name == $tag) | .assets[] | select(.name | test($pat)) | .updated_at)')
			;;
	esac
	echo "$updated_at"
}

date_to_sec() {
	if date --version >/dev/null 2>&1; then
		date -d "$1" +%s
	else
		date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
	fi
}

checker(){
	local repo=$1 tag_type=$2
	shift 2
	local checks=("$@")
	local ur_repo="${repository:-$GITHUB_REPOSITORY}"

	local date1 date1_sec
	date1=$(get_date "$repo" "$tag_type" "(\.jar|\.rvp|\.mpp|\.apk)$")
	if [ -z "$date1" ] || [ "$date1" = "null" ]; then
		echo -e "\e[31mFailed to fetch upstream release date for $repo\e[0m"
		[ -n "$GITHUB_OUTPUT" ] && echo "new_patch=0" >> "$GITHUB_OUTPUT"
		return 0
	fi
	date1_sec=$(date_to_sec "$date1")

	local needs_build=0
	local outdated_apps=()
	for entry in "${checks[@]}"; do
		local app_label="" check="$entry"
		if [[ "$entry" == *":"* ]]; then
			app_label="${entry%%:*}"
			check="${entry#*:}"
		fi
		local date2 date2_sec
		date2=$(get_date "$ur_repo" "all" "$check")
		if [ -z "$date2" ] || [ "$date2" = "null" ]; then
			echo -e "\e[33mNo release found matching '$check' in $ur_repo\e[0m"
			needs_build=1
			if [ -n "$app_label" ]; then
				outdated_apps+=("$app_label")
				continue
			fi
			break
		fi
		date2_sec=$(date_to_sec "$date2")
		if [ "$date1_sec" -gt "$date2_sec" ]; then
			echo -e "\e[33mRelease for '$check' ($date2) is older than upstream ($date1)\e[0m"
			needs_build=1
			if [ -n "$app_label" ]; then
				outdated_apps+=("$app_label")
				continue
			fi
			break
		fi
	done

	if [ "$needs_build" -eq 1 ]; then
		if [ -n "$GITHUB_OUTPUT" ]; then
			echo "new_patch=1" >> "$GITHUB_OUTPUT"
			if [ ${#outdated_apps[@]} -gt 0 ]; then
				echo "targets=${outdated_apps[*]}" >> "$GITHUB_OUTPUT"
			fi
		fi
		echo -e "\e[32mNew patch, building... (${outdated_apps[*]:-all})\e[0m"
	else
		[ -n "$GITHUB_OUTPUT" ] && echo "new_patch=0" >> "$GITHUB_OUTPUT"
		echo -e "\e[32mOld patch, not build.\e[0m"
	fi
}
checker "$@"
