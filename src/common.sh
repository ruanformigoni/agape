#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : common
# @created     : Tuesday Oct 04, 2022 02:49:02 -03
######################################################################

# shellcheck disable=2155

set -e

function die()
{
  exit 1
}

function msg()
{
  echo "-- $*" >&2
}

function params_validate()
{
  # Check params and validate files
  [ $# -eq 3 ] || { msg "Invalid number of arguments"; die; }

  # Convert path to absolute
  local src_dir="$(readlink -f "$2")"

  [ -d "$src_dir" ] || { msg "Invalid src dir ${src_dir}"; die; }

  # Functor to check file validity
  local f_validate

  { read -r -d '\0' f_validate < <(sed -E 's/^\s+://'); } <<-END
    :[ -f "{}" ] || { msg "Invalid file: {}"; die; }\0
	END

  local rom="$(basename "$3")"
  eval "${f_validate//"{}"/"$src_dir/rom/$rom"}"

  local core
  if [ -d "$src_dir/core" ]; then
    read -r core <<< "$(find "$src_dir/core" -regextype posix-extended -iregex ".*so")"
    eval "${f_validate//"{}"/"${core}"}"
  else
    core="null"
  fi

  local cover
  read -r cover <<< "$(find "$src_dir/icon" -regextype posix-extended -iregex ".*(jpg|png|svg)" -print -quit)"
  eval "${f_validate//"{}"/"${cover}"}"

  local bios
  if [ -d "$src_dir/bios" ]; then
    read -r bios <<< "$(find "$src_dir/bios" -regextype posix-extended -iregex ".*(bin|pup)")"
    eval "${f_validate//"{}"/"${bios}"}"
  else
    bios="null"
  fi

  # Get name and normalize to dash separated lowercase
  local name="${1// /-}"
  local name="$(echo "$name" | tr '[:upper:]' '[:lower:]')"

  # Return
  echo -e "$name\n$src_dir\n$bios\n$core\n$cover\n$rom"
}

function dir_build_create()
{
  local build_dir="build"

  mkdir -p "$build_dir"

  msg "build dir: $(readlink -f ./"${build_dir}")"

  echo "$build_dir"
}

function dir_appdir_create()
{
  local appdir="AppDir"

  if [ -d "$appdir" ]; then
    rm -rf "$appdir";
  fi

  mkdir -p AppDir
  mkdir -p AppDir/app
  mkdir -p AppDir/usr/bin
  mkdir -p AppDir/usr/share/icons
}

function appimagetool_download()
{
  # Get appimagetool
  [ ! -f "./appimagetool" ] && wget -q --show-progress --progress=bar:noscroll -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage

  # Make executable
  chmod +x appimagetool
}

function files_copy()
{
  local name="$1"
  local dir="$2"
  local bios="$3"
  local core="$4"
  local cover="$5"

  # Rom
  cp -r "$dir"/rom/* AppDir/app/

  # Copy image to AppDir
  convert "$cover" AppDir/"${name}".png

  # Bios
  if [ "$bios" != "null" ]; then
    cp "$bios" AppDir/app/
  fi

  # Core
  if [ "$core" != "null" ]; then
    cp "$core" AppDir/app/
  fi
}

function desktop_entry_create()
{
  local name="$1"

  # Create runner script
  { sed -E 's/^\s+://' | tee AppDir/"${name}.desktop"; } <<-END
    :[Desktop Entry]
    :Name=${name}
    :Exec=/usr/bin/bash
    :Icon=${name}
    :Type=Application
    :Categories=Utility;
	END
}

function appdir_build()
{
  ARCH=x86_64 ./appimagetool AppDir
}