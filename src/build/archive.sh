#!/bin/bash
# Morphe Community build - Archive recipes
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

community_patch() {
	patch "$1" "$2" "morphe"
	if [ "${detachPlayStoreUpdates:-false}" = true ]; then
		morphe_disable_play_store_updates "$1" "$2"
	fi
	unset detachPlayStoreUpdates
}

derevanced_dl(){
	dl_gh "morphe-desktop" "MorpheApp" "latest"
	morphe_universal_dl
	dl_gh "De-Vanced" "RookieEnough" "$tag"
}

rushi_dl(){
	dl_gh "morphe-desktop" "MorpheApp" "latest"
	morphe_universal_dl
	dl_gh "morphe-patches" "rushiranpise" "$tag"
}

binarymend_dl(){
	dl_gh "morphe-desktop" "MorpheApp" "latest"
	morphe_universal_dl
	dl_gh "morphe-patches" "binarymend" "$tag"
}

hoo-dles_dl(){
	dl_gh "morphe-desktop" "MorpheApp" "latest"
	morphe_universal_dl
	dl_gh "morphe-patches" "hoo-dles" "$tag"
}

hooman_dl(){
	dl_gh "morphe-desktop" "MorpheApp" "latest"
	morphe_universal_dl
	dl_gh "hoomans-morphe-patches" "arandomhooman" "$tag"
}

photos() {
	APP_NAME="google-photos"
	VARIANT="drv"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	derevanced_dl
	get_patches_key "gg-photos"
	get_apk "com.google.android.apps.photos" "gg-photos-arm64-v8a" "bundle" "arm64-v8a" "320-640dpi" "Android 12L+"

	release_exists && return 0

	community_patch "gg-photos-arm64-v8a" "derevanced"
}

messenger() {
	APP_NAME="messenger"
	VARIANT="drv"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	derevanced_dl
	get_patches_key "messenger"
	get_apk "com.facebook.orca" "messenger-arm64-v8a" "apk" "arm64-v8a" "nodpi" "Android 9.0+"

	release_exists && return 0

	community_patch "messenger-arm64-v8a" "derevanced"
}

strava() {
	APP_NAME="strava"
	VARIANT="rushi"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	rushi_dl
	get_patches_key "strava"
	get_apk_uptodown "com.strava" "strava-arm64-v8a" "bundle" || \
	get_apk_chplay "com.strava" "strava-arm64-v8a" "bundle"

	release_exists && return 0

	community_patch "strava-arm64-v8a" "rushi"
}

fotmob() {
	APP_NAME="fotmob"
	VARIANT="hoo-dles"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	hoo-dles_dl
	get_patches_key "fotmob"
	get_apk "com.mobilefootie.wc2010" "fotmob-arm64-v8a" "bundle" "universal" "nodpi" "Android 12L+"

	release_exists && return 0

	community_patch "fotmob-arm64-v8a" "hoo-dles"
}

windy() {
	APP_NAME="windy"
	VARIANT="hoo-dles"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	hoo-dles_dl
	get_patches_key "windy"
	get_apk "com.windyty.android" "windy-arm64-v8a" "bundle" "universal" "120-640dpi" "Android 12L+"

	release_exists && return 0

	community_patch "windy-arm64-v8a" "hoo-dles"
}

moonreader() {
	APP_NAME="moonreader"
	VARIANT="binarymend"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	binarymend_dl
	get_patches_key "moonreader"
	get_apk "com.flyersoft.moonreader" "moonreader-arm64-v8a" "bundle"

	release_exists && return 0

	community_patch "moonreader-arm64-v8a" "binarymend"
}

adguard() {
	APP_NAME="adguard"
	VARIANT="rushi"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	rushi_dl
	get_patches_key "adguard"
	get_apk "com.adguard.android" "adguard" "apk"

	release_exists && return 0

	community_patch "adguard" "rushi"
}

poweramp() {
	APP_NAME="poweramp"
	VARIANT="hooman"
	echo "APP_NAME=$APP_NAME" >> $GITHUB_ENV
	echo "VARIANT=$VARIANT" >> $GITHUB_ENV

	hooman_dl
	get_patches_key "poweramp"
	version="build-1024-bundle-play"
	get_apk "com.maxmpz.audioplayer" "poweramp" "bundle"

	release_exists && return 0

	community_patch "poweramp" "hooman"
}

case "$1" in
	messenger)
		messenger
		;;
	photos)
		photos
		;;
	strava)
		strava
		;;
	fotmob)
		fotmob
		;;
	windy)
		windy
		;;
	moonreader)
		moonreader
		;;
	adguard)
		adguard
		;;
	poweramp)
		poweramp
		;;
esac
