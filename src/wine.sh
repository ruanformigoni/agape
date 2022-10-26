#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : wine
# @created     : Thursday Oct 13, 2022 10:40:26 -03
######################################################################

#shellcheck disable=2155
#shellcheck source=/dev/null

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "$SCRIPT_DIR/common.sh"

# Get wine appimage and define wine alias
function wine_download()
{
  local url

  url=$(curl -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mmtrt/WINE_AppImage/releases 2>&1 |
    grep -Eo "https://.*continuous-staging/wine-staging_.*\.AppImage\"")

  msg "wine: ${url%\"}"

  [ ! -f "AppDir/usr/bin/wine" ] && \
    wget -q --show-progress --progress=bar:noscroll -O AppDir/usr/bin/wine "${url%\"}"

  chmod +x AppDir/usr/bin/wine
  # shellcheck disable=2139
  WINE="$(pwd)/AppDir/usr/bin/wine"
}

function arch_select()
{
  msg "Please select the architecture" >&2
  select i in "win32" "win64"; do
    [ "$i" ] || continue;
    echo "$i"; break
  done
}

function wine_configure()
{
  "$WINE" --version

  export WINEPREFIX="$(pwd)/AppDir/app/wine"

  if [ ! -d "$WINEPREFIX" ]; then
    export WINEARCH="$(arch_select)"
    "$WINE" winetricks fontsmooth=rgb
    "$WINE" winetricks dxvk
  fi

  declare -A opts

  for i in $("$WINETRICKS" list-all | awk '!/=+/ { print $1 }'); do
    opts["$i"]=1
  done

  pwd
  msg "winetricks, use it to install dependencies, leave it blank to continue"
  while :; do
    echo -n "winetricks> "
    read -r args
    # Stop on empty input
    [ "$args" ] || break
    # Check if is bash cmd
    for i in "${args[@]}"; do
      [ "${opts[$i]}" ] || { eval "${args[*]}" || true; continue 2; }
    done
    # If not call winetricks
    "$WINE" winetricks "$args" || continue
  done
}

function wine_install()
{
  pwd
  msg "wine, install desired applications, leave it blank to continue"
  while :; do
    echo -n "wine> "
    read -r args
    # Stop on empty input
    [ "$args" ] || break
    # Check if config
    [ "${args[*]}" = "config" ] && { "$WINE"; continue; }
    # Check if is bash cmd
    [[ ! "${args[*]}" =~ .*\.exe ]] && { eval "${args[*]}" || true; continue; }
    # Exec as wine arg
    "$WINE" "$args"
  done
}

function wine_executable_select()
{
  msg "Select the game's executable"
  readarray -t files <<< "$(find "AppDir/app/wine" -not -path "*drive_c/windows/*.exe" -iname "*.exe")"

  local executable
  select i in "${files[@]}"; do
    [ "$i" ] || continue;
    executable="$i"; break
  done

  # Get directory to move out from drive c:
  local dir_installation
  dir_installation="$(dirname "$executable")"
  dir_installation="${dir_installation//*drive_c\/}"
  dir_installation="${dir_installation//\/*}"

  # Create directory to store installed files
  dir_target="AppDir/app/rom"
  mkdir -p "$dir_target"

  # Move to target directory
  msg "Moving $dir_installation to $dir_target"
  mv "AppDir/app/wine/drive_c/$dir_installation" "$dir_target"

  echo -e "$dir_installation\n$executable"
}

function runner_create()
{
  local path_exec

  # Binary directory path under c: drive
  path_install="$1"

  # Binary path under AppDir
  path_exec="$2"
  path_exec="${path_exec##*AppDir/app/}"

  # Create runner script
  { sed -E 's/^\s+://' | tee AppDir/AppRun; } <<-END
    :#!/usr/bin/env bash
    :
    :set -e
    :
    :# Wine executable
    :WINE="\$APPDIR/usr/bin/wine"
    :
    :if [[ "\$(basename "\${APPIMAGE}")" =~ \.\.AppImage ]]; then
    :  # Set hidden config dir
    :  CFGDIR="\$(dirname "\$APPIMAGE")/\$(basename "\$APPIMAGE").config"
    :else
    :  # Set visible config dir
    :  CFGDIR="\$(dirname "\$APPIMAGE")/.\$(basename "\$APPIMAGE").config"
    :fi
    :
    :# Path to appimage mountpoint
    :MNTDIR="\$APPDIR"
    :
    :# Create wine prefix if not exists
    :export WINEPREFIX="\$CFGDIR/wine"
    :if [ ! -d "\$WINEPREFIX" ]; then
    :  mkdir -p "\$CFGDIR"
    :  cp -r "\$MNTDIR/app/wine" "\$CFGDIR"
    :fi
    :
    :# Create/Update symlink to the application directory
    :rm -f "\$CFGDIR/wine/drive_c/$path_install"
    :ln -s "\$MNTDIR/app/rom/$path_install" "\$CFGDIR/wine/drive_c/$path_install"
    :
    :cd "\$(dirname "\$CFGDIR/$path_exec")"
    :
    :exec="$(basename "$path_exec")"
    :
    :if [ "\$@" ]; then
    :  "\$WINE" "\$@"
    :else
    :  "\$WINE" "\$exec"
    :fi
	END

  # Allow execute
  chmod +x AppDir/AppRun

  msg "AppRun written, make further changes to it if you desire, then press enter..."
  read -r
}

function main()
{
  # Validate params
  readarray -t ret <<< "$(params_validate "wine" "$@")"

  local name="${ret[0]}"
  local cover="${ret[4]}"

  # Create dirs
  build_dir="$(dir_build_create)"; cd "${build_dir}"

  dir_appdir_create

  # Download tools
  appimagetool_download

  # Install and configure application
  wine_download
  wine_configure
  wine_install
  readarray -t ret <<< "$(wine_executable_select)"

  # Create runner script
  runner_create "${ret[0]}" "${ret[1]}"

  # Copy cover
  convert "$cover" "AppDir/${name}.png"

  # Create desktop entry
  desktop_entry_create "$name"

  # Build appimage
  appdir_build
}

main "$@"

#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
