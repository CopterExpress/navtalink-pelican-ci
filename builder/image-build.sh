#! /usr/bin/env bash

#
# Script for build the image. Used builder script of the target repo
# For build: docker run --privileged -it --rm -v /dev:/dev -v $(pwd):/builder/repo smirart/builder
#
# Copyright (C) 2020 Copter Express Technologies
#
# Author: Artem Smirnov <urpylka@gmail.com>
# Author: Andrey Dvornikov <dvornikov-aa@yandex.ru>
#

set -e # Exit immidiately on non-zero result

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:='noninteractive'}
export LANG=${LANG:='C.UTF-8'}
export LC_ALL=${LC_ALL:='C.UTF-8'}

echo_stamp() {
  # TEMPLATE: echo_stamp <TEXT> <TYPE>
  # TYPE: SUCCESS, ERROR, INFO

  # More info there https://www.shellhacks.com/ru/bash-colors/

  TEXT="$(date '+[%Y-%m-%d %H:%M:%S]') $1"
  TEXT="\e[1m$TEXT\e[0m" # BOLD

  case "$2" in
    SUCCESS)
    TEXT="\e[32m${TEXT}\e[0m";; # GREEN
    ERROR)
    TEXT="\e[31m${TEXT}\e[0m";; # RED
    *)
    TEXT="\e[34m${TEXT}\e[0m";; # BLUE
  esac
  echo -e ${TEXT}
}

BUILDER_DIR="/builder"
REPO_DIR="${BUILDER_DIR}/repo"
SCRIPTS_DIR="${REPO_DIR}/builder"
IMAGES_DIR="${REPO_DIR}/images"
LIB_DIR="${REPO_DIR}/lib"

function gh_curl() {
  curl -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
       -H "Accept: application/vnd.github.v3.raw" \
       $@
}

[[ ! -d ${SCRIPTS_DIR} ]] && (echo_stamp "Directory ${SCRIPTS_DIR} doesn't exist" "ERROR"; exit 1)
[[ ! -d ${IMAGES_DIR} ]] && mkdir ${IMAGES_DIR} && echo_stamp "Directory ${IMAGES_DIR} was created successful" "SUCCESS"

if [[ -z ${TRAVIS_TAG} ]]; then IMAGE_VERSION="$(cd ${REPO_DIR}; git log --format=%h -1)"; else IMAGE_VERSION="${TRAVIS_TAG}"; fi
# IMAGE_VERSION="${TRAVIS_TAG:=$(cd ${REPO_DIR}; git log --format=%h -1)}"
REPO_URL="$(cd ${REPO_DIR}; git remote --verbose | grep origin | grep fetch | cut -f2 | cut -d' ' -f1 | sed 's/git@github\.com\:/https\:\/\/github.com\//')"
REPO_NAME="navtalink-pelican-ci"
IMAGE_NAME="navtalink-pelican_${IMAGE_VERSION}.img"
IMAGE_PATH="${IMAGES_DIR}/${IMAGE_NAME}"

get_asset() {
  # TEMPLATE: get_asset <REPO_NAME> <VERSION> <ASSET_NAME> <OUTPUT_FILE>
  local REPO_NAME="$1"
  local VERSION="$2"
  local ASSET_NAME="$3"
  local OUTPUT_FILE="$4"

  echo_stamp "Downloading \"$ASSET_NAME\" from assets ($REPO_NAME:$VERSION)"
  local parser=". | map(select(.tag_name == \"${VERSION}\"))[0].assets | map(select(.name == \"${ASSET_NAME}\"))[0].id"

  asset_id=`gh_curl -s https://api.github.com/repos/${REPO_NAME}/releases | jq "$parser"`
  if [ "$asset_id" = "null" ]; then
    echo "ERROR: version not found ${VERSION}"
    exit 1
  fi;

  wget -q --auth-no-challenge --header='Accept:application/octet-stream' \
    "https://${GITHUB_OAUTH_TOKEN}:@api.github.com/repos/${REPO_NAME}/releases/assets/${asset_id}" \
    -O "${OUTPUT_FILE}"
  echo_stamp "Downloading complete" "SUCCESS"
}

get_image_asset() {
  # TEMPLATE: get_image_asset <IMAGE_PATH>
  local BUILD_DIR=$(dirname $1)
  local ORIGIN_IMAGE_NAME="navtalink_${ORIGIN_IMAGE_VERSION}.img"
  local ORIGIN_IMAGE_ZIP="${ORIGIN_IMAGE_NAME}.zip"

  if [ ! -e "${BUILD_DIR}/${ORIGIN_IMAGE_ZIP}" ]; then
    echo_stamp "Downloading original NavTALink image from assets"
    get_asset "${ORIGIN_IMAGE_REPO}" "${ORIGIN_IMAGE_VERSION}" "${ORIGIN_IMAGE_ZIP}" "${BUILD_DIR}/${ORIGIN_IMAGE_ZIP}"
  else echo_stamp "Original NavTALink image already downloaded"; fi

  echo_stamp "Unzipping original NavTALink image" \
  && unzip -p "${BUILD_DIR}/${ORIGIN_IMAGE_ZIP}" ${ORIGIN_IMAGE_NAME} > $1 \
  && echo_stamp "Unzipping complete" "SUCCESS" \
  || (echo_stamp "Unzipping was failed!" "ERROR"; exit 1)
}

apt-get update
apt-get install -y curl

get_image_asset ${IMAGE_PATH}

# Make free space
${BUILDER_DIR}/image-resize.sh ${IMAGE_PATH} max '7G'

# Temporary disable ld.so
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} exec ${SCRIPTS_DIR}'/image-ld.sh' disable

# Include dotfiles in globs (asterisks)
shopt -s dotglob

${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} copy ${SCRIPTS_DIR}'/assets/init_rpi.sh' '/root/'
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} exec ${SCRIPTS_DIR}'/image-init.sh' ${ORIGIN_IMAGE_VERSION} ${ORIGIN_IMAGE_VERSION}

# Copy updated config for wifibroadcast
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} copy ${SCRIPTS_DIR}'/assets/wifibroadcast.cfg.drone' '/home/pi/navtalink/wifibroadcast.cfg.drone'
# Copy PixyMon sources
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} copy ${LIB_DIR}'/pixymon-1.0.2beta/' '/home/pi/'
# Copy xstartup
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} copy ${SCRIPTS_DIR}'/assets/xstartup' '/home/pi/.vnc/'
# Copy vncserver service
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} copy ${SCRIPTS_DIR}'/assets/vncserver@:1.service' '/lib/systemd/system/'
# Software install
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} exec ${SCRIPTS_DIR}'/image-software.sh'

# Enable ld.so.preload
${BUILDER_DIR}/image-chroot.sh ${IMAGE_PATH} exec ${SCRIPTS_DIR}'/image-ld.sh' enable

${BUILDER_DIR}/image-resize.sh ${IMAGE_PATH}
