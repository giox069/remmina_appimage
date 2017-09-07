#!/bin/bash

# Make AppImage for remmina

WORKDIR="$HOME/remmina_AppImage"
APP=Remmina
ENABLE_DI=yes


# Delete blacklisted files
loc_delete_blacklisted()
{
  BLACKLISTED_FILES=$(cat_file_from_url https://github.com/AppImage/AppImages/raw/master/excludelist | sed 's|#.*||g')
  echo $BLACKLISTED_FILES
  for FILE in $BLACKLISTED_FILES ; do
    if [[ $FILE != libpango* ]];
    then
      FILES="$(find . -name "${FILE}" -not -path "./usr/optional/*")"
      for FOUND in $FILES ; do
        rm -vf "$FOUND" "$(readlink -f "$FOUND")"
      done
    fi
  done

  # Do not bundle developer stuff
  rm -rf usr/include || true
  rm -rf usr/lib/cmake || true
  rm -rf usr/lib/pkgconfig || true
  find . -name '*.la' | xargs -i rm {}
}

echo WORKDIR=$WORKDIR

test -d "$WORKDIR" || mkdir "$WORKDIR"
test -d "$WORKDIR" || (echo "Cannot create $WORKDIR directory" && exit 1)

IFS='.' read DEBIAN_VERSION DEBIAN_VERSION_MINOR < /etc/debian_version
if [ "$DEBIAN_VERSION" != "8" ];
then
	echo "Debian 8 is required, but $DEBIAN_VERSION.$DEBIAN_VERSION_MINOR found."
	exit 1
fi

cd $WORKDIR

echo "################"
echo "If running inside a container, please set it to privileged"
echo "lxc config set guest 'security.privileged' true"
echo "See this bug: https://github.com/systemd/systemd/issues/719"
echo "###############"
read -p "Press enter to continue, or ^C to abort"

lastupdateage=$(( `date +%s` - `stat -L --format %Y /var/cache/apt/pkgcache.bin ` ))
echo "Last apt update age: " $lastupdateage
if [[ $lastupdateage -gt 7200 ]];
then
	apt update || exit 1
	apt -y dist-upgrade || exit 1
	echo "Please reboot and restart this script"
	exit 1
fi



echo "Installing base tools"
apt -y install vim nano less wget dbus desktop-file-utils fuse gpgv2

apt -y install build-essential \
	libssh-dev cmake libx11-dev libxext-dev libxinerama-dev \
	libxcursor-dev libxdamage-dev libxv-dev libxkbfile-dev libasound2-dev \
	libcups2-dev libxml2 libxml2-dev \
	libxrandr-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
	libxi-dev libavutil-dev \
	libavcodec-dev libxtst-dev libgtk-3-dev libgcrypt11-dev  libpulse-dev \
	libvte-2.91-dev libxkbfile-dev libtelepathy-glib-dev libjpeg-dev \
	libgnutls28-dev libgnome-keyring-dev libavahi-ui-gtk3-dev libvncserver-dev \
	libappindicator3-dev intltool libsecret-1-dev libwebkit2gtk-4.0-dev libsystemd-dev \
	wget \
	git || (echo "Unable to install all needed packages" && exit 1)

# Inspiration: https://github.com/probonopd/AppImages/blob/master/recipes/meta/Recipe
LOWERAPP=${APP,,}

test -d "./$APP" || mkdir ./$APP

if [ ! -e functions.sh ] ; then
	wget -q https://github.com/probonopd/AppImages/raw/master/functions.sh -O ./functions.sh
fi
. ./functions.sh


cd "$WORKDIR/$APP"
test -d "./$APP.AppDir/" && rm -rf ./$APP.AppDir/
test -d "./source/" || mkdir ./source
INSTBASE="$WORKDIR/$APP/$APP.AppDir"

cd "$WORKDIR/$APP/source"
ARCH=`uname -m`


# Now build FreeRDP
if [ ! -d ./FreeRDP ];
then
	git clone https://github.com/FreeRDP/FreeRDP.git || (echo "FreeRDP clone failed" && exit 1)
	cd ./FreeRDP
else
	cd ./FreeRDP
	git pull
#	git clean -fxd
fi
PARAMS="-DWITH_CUPS=on -DWITH_WAYLAND=off -DWITH_PULSE=on"
PARAMS="$PARAMS -DWITH_MANPAGES=off -DWITH_CLIENT=off -DWITH_LIBSYSTEMD=off -DWITH_OSS=OFF -DWITH_ALSA=OFF"
PARAMS="$PARAMS -DCMAKE_INSTALL_PREFIX:PATH=$INSTBASE/usr ."
echo $ARCH
if [[ "$ARCH" == i?86 || $ARCH == x86_64 ]];
then
	PARAMS="-DWITH_SSE2=ON $PARAMS"
fi
echo "cmake $PARAMS"
#cmake $PARAMS || (echo "cmake FreeRDP failed" && exit 1)
#make -j 4 || (echo "FreeRDP compilation failed" && exit 1)
make install || (echo "FreeRDP install failed" && exit 1)

# Now build Remmina
cd "$WORKDIR/$APP/source"
BRANCH="next"
BRANCH="runtimepaths"
if [ ! -d ./Remmina ];
then
	git clone https://github.com/FreeRDP/Remmina.git -b "$BRANCH" || (echo "Remmina clone failed" && exit 1)
	cd ./Remmina
else
	cd ./Remmina
	git checkout "$BRANCH"
	git pull
	git clean -fxd
fi
PARAMS="-DCMAKE_INSTALL_PREFIX:PATH=$INSTBASE/usr -DCMAKE_PREFIX_PATH=$INSTBASE/usr "
PARAMS="$PARAMS -D REMMINA_RUNTIME_UIDIR=./share/remmina/ui"
PARAMS="$PARAMS -D REMMINA_RUNTIME_PLUGINDIR=./lib/remmina/plugins"
PARAMS="$PARAMS -D REMMINA_RUNTIME_DATADIR=./share/appdata"
PARAMS="$PARAMS -D REMMINA_RUNTIME_LOCALEDIR=./share/locale"
PARAMS="$PARAMS -D REMMINA_RUNTIME_EXTERNAL_TOOLS_DIR=./share/remmina/extenal_tools"
PARAMS="$PARAMS --build=build ."
cmake $PARAMS || (echo "cmake Remmina failed" && exit 1)
make -j 2 || (echo "Remmina compilation failed" && exit 1)
make install || (echo "Remmina install failed" && exit 1)

# Get version from config.h
test -f config.h || (echo "config.h not found after compiling remmina" && exit 1)
VERSION=`sed -n '/#define VERSION/s/^.\+\"\(.\+\)\"/\1/p' < config.h`
VERSION=${VERSION//-/_}
test -z $VERSION && (echo "Unable to find version inside config.h" && exit 1)
GITREV=`sed -n '/#define REMMINA_GIT_REVISION/s/^.\+\"\(.\+\)\"/\1/p' < config.h`
VERSION="${VERSION}_$GITREV"

echo "Found remmina VERSION=$VERSION"

# Start composing AppImage

cd "$INSTBASE"


# Copy main desktop icon
cp "usr/share/icons/hicolor/scalable/apps/remmina.svg" .

get_apprun

get_desktop

DESKTOP=$(find . -name '*.desktop' | sort | head -n 1)
echo "DESKTOP file found in $DESKTOP"
test -z "$DESKTOP" && (echo "Desktop file not found, aborting" || exit 1)

fix_desktop "$DESKTOP"

desktop-file-validate "$DESKTOP" || exit 1
ORIG=$(grep -o "^Exec=.*$" "${DESKTOP}" | head -n 1| cut -d " " -f 1)
REPL=$(basename $(grep -o "^Exec=.*$" "${DESKTOP}" | head -n 1 | cut -d " " -f 1 | sed -e 's|Exec=||g'))
sed -i -e 's|'"${ORIG}"'|Exec='"${REPL}"'|g' "${DESKTOP}"

# patch_usr
# Patching only the executable files seems not to be enough for some apps
if [ ! -z "${_binpatch}" ] ; then
  find usr/ -type f -exec sed -i -e 's|/usr|././|g' {} \;
  find usr/ -type f -exec sed -i -e 's@././/bin/env@/usr/bin/env@g' {} \;
fi

# Don't suffer from NIH; use LD_PRELOAD to override calls to /usr paths
if [ ! -z "${_union}" ] ; then
  mkdir -p usr/src/
  wget -q "https://raw.githubusercontent.com/mikix/deb2snap/master/src/preload.c" -O - | \
  sed -e 's|SNAPPY|UNION|g' | sed -e 's|SNAPP|UNION|g' | sed  -e 's|SNAP|UNION|g' | \
  sed -e 's|snappy|union|g' > usr/src/libunionpreload.c
  gcc -shared -fPIC usr/src/libunionpreload.c -o libunionpreload.so -ldl -DUNION_LIBNAME=\"libunionpreload.so\"
  strip libunionpreload.so
fi


if [ "$ENABLE_DI" = "yes" ] ; then
  get_desktopintegration $LOWERAPP
fi

# Fix desktop files that have file endings for icons
sed -i -e 's|\.png||g' *.desktop || true
sed -i -e 's|\.svg||g' *.desktop || true
sed -i -e 's|\.svgz||g' *.desktop || true
sed -i -e 's|\.xpm||g' *.desktop || trueA

copy_deps
copy_deps

loc_delete_blacklisted

# Fix libpulseaudio position
if [ -d "./usr/lib/x86_64-linux-gnu/pulseaudio/" ] ; then
  mv ./usr/lib/x86_64-linux-gnu/pulseaudio/* ./usr/lib/x86_64-linux-gnu/
  rm -r ./usr/lib/x86_64-linux-gnu/pulseaudio
fi

echo "Going out..."

# Go out of AppImage
cd ..
pwd

generate_type2_appimage
ls -lh ../out/*.AppImage



