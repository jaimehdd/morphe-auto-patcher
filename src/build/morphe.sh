#!/bin/bash
# Morphe build
source ./src/build/utils.sh

use_beta="${use_beta:-false}"

morphe_dl() {
	local patches_tag="latest"
	[ "$use_beta" = true ] && patches_tag="prerelease"
	dl_gh "morphe-patches" "MorpheApp" "$patches_tag"
	dl_gh "morphe-desktop" "MorpheApp" "$patches_tag" "true"
}

youtube() {
	APP_NAME="youtube"
	VARIANT="morphe"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	morphe_dl
	get_patches_key "youtube-morphe"
	prefer_version="$youtube_experimental_support"
	get_apk "com.google.android.youtube" "youtube" "apk"

	release_exists && return 0

	patch "youtube" "morphe" "morphe" "arm64-v8a"
}

youtube-music() {
	APP_NAME="youtube-music"
	VARIANT="morphe"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	morphe_dl
	get_patches_key "youtube-music-morphe"
	prefer_version="$youtube_music_experimental_support"
	get_apk "com.google.android.apps.youtube.music" "youtube-music-arm64-v8a" "apk" "arm64-v8a"

	release_exists && return 0

	patch "youtube-music-arm64-v8a" "morphe" "morphe"
}

case "$1" in
	youtube|youtube-morphe)
		youtube
		;;
	youtube-music|youtube-music-morphe)
		youtube-music
		;;
esac
