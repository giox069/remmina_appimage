#!/bin/bash

# Make AppImage for remmina

WORKDIR="$HOME/remmina_AppImage_workdir"
APP=Remmina
ENABLE_DI=yes

abort() { echo "$*" ; exit 1; }

# Saves the script execution dir
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for i in "$@"
do
case $i in
    --skip-syspkg)
    SKIP_SYSPKG=YES
    shift # past argument with no value
    ;;
    --skip-freerdp-compilation)
    SKIP_FREERDP_COMPILATION=YES
    shift # past argument with no value
    ;;
    *)
            # unknown option
    ;;
esac
done


echo WORKDIR=$WORKDIR

test -d "$WORKDIR" || mkdir "$WORKDIR"
test -d "$WORKDIR" || abort "Cannot create $WORKDIR directory"

IFS='.' read DEBIAN_VERSION DEBIAN_VERSION_MINOR < /etc/debian_version
if [ "$DEBIAN_VERSION" != "8" ];
then
	abort "Debian 8 is required, but $DEBIAN_VERSION.$DEBIAN_VERSION_MINOR found."
fi

cd $WORKDIR

if [ -z "${SKIP_SYSPKG}" ];
then

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
		apt update || abort "apt update failed"
		apt -y dist-upgrade || abort "dist-upgrade failed"
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
		gnome-themes-standard-data \
		wget \
		git || abort "Unable to install all needed packages"
fi
	
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


if [ -z "${SKIP_FREERDP_COMPILATION}" ];
then
	# Now build FreeRDP
	if [ ! -d ./FreeRDP ];
	then
		git clone https://github.com/FreeRDP/FreeRDP.git || abort "FreeRDP clone failed"
		cd ./FreeRDP
	else
		cd ./FreeRDP
		git pull
		git clean -fxd
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
	cmake $PARAMS || abort "cmake FreeRDP failed"
	make -j 4 || abort "FreeRDP compilation failed"
else
	cd ./FreeRDP || abort "Unable to chdir into FreeRDP dir"
fi
make install || abort "FreeRDP install failed"

# Now build Remmina
cd "$WORKDIR/$APP/source"
BRANCH="next"
if [ ! -d ./Remmina ];
then
	git clone https://github.com/FreeRDP/Remmina.git -b "$BRANCH" || abort "Remmina clone failed"
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
PARAMS="$PARAMS -D REMMINA_RUNTIME_EXTERNAL_TOOLS_DIR=./share/remmina/external_tools"
PARAMS="$PARAMS --build=build ."
cmake $PARAMS || abort "cmake Remmina failed"
make -j 2 || abort "Remmina compilation failed"
make install || abort "Remmina install failed"

# Get version from config.h
test -f config.h || abort "config.h not found after compiling remmina"
VERSION=`sed -n '/#define VERSION/s/^.\+\"\(.\+\)\"/\1/p' < config.h`
VERSION=${VERSION//-/_}
test -z $VERSION && abort "Unable to find version inside config.h"
GITREV=`sed -n '/#define REMMINA_GIT_REVISION/s/^.\+\"\(.\+\)\"/\1/p' < config.h`
VERSION="${VERSION}_$GITREV"

echo "Found remmina VERSION=$VERSION"

# Start composing AppImage

cd "$INSTBASE"


# Copy main desktop icon
cp "usr/share/icons/hicolor/scalable/apps/remmina.svg" .

# .desktop file
get_desktop


DESKTOP=$(find . -name '*.desktop' | sort | head -n 1)
echo "DESKTOP file found in $DESKTOP"
test -z "$DESKTOP" && abort "Desktop file not found, aborting"

fix_desktop "$DESKTOP"

desktop-file-validate "$DESKTOP" || exit 1
ORIG=$(grep -o "^Exec=.*$" "${DESKTOP}" | head -n 1| cut -d " " -f 1)
REPL=$(basename $(grep -o "^Exec=.*$" "${DESKTOP}" | head -n 1 | cut -d " " -f 1 | sed -e 's|Exec=||g'))
sed -i -e 's|'"${ORIG}"'|Exec='"${REPL}"'|g' "${DESKTOP}"

# patch_usr
# Patching only the executable files seems not to be enough for some apps
#if [ ! -z "${_binpatch}" ] ; then
#  find usr/ -type f -exec sed -i -e 's|/usr|././|g' {} \;
#  find usr/ -type f -exec sed -i -e 's@././/bin/env@/usr/bin/env@g' {} \;
#fi

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

# Copy all icons which are listed in remmina_global_icons.lst
ICONLISTFILE="$SCRIPTDIR/remmina_global_icons.lst"
ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme)
GLOBAL_ICONPATH=/usr/share/icons/${ICON_THEME:1:-1}

[ -f $ICONLISTFILE ] || abort "Unable to find $ICONLISTFILE"
for i in `cat $ICONLISTFILE;`
do
	ICLIST=`find $GLOBAL_ICONPATH -name "$i.*"`
	for ic in $ICLIST;
	do
		RELPATH=${ic##${GLOBAL_ICONPATH}}
		DESTDIR="./usr/share/icons/hicolor/$(dirname "${RELPATH}")"
		[ -d "$DESTDIR" ] || mkdir -p "$DESTDIR"
		[ -d "$DESTDIR" ] || abort "Cannot create $DESTDIR"
		cp "$ic" "$DESTDIR" || abort "Cannot copy file to $DESTDIR"
	done
done

GDKPIXBUFQUERYLOADERS=$(type -path gdk-pixbuf-query-loaders)
cp "$GDKPIXBUFQUERYLOADERS" ./usr/bin || abort "Unable to copy gdk-pixbuf-query-loaders executable"

# Copy GDK pixbuf loaders in our environment
LOADERS=`gdk-pixbuf-query-loaders | grep "/libpix.\+so" | sed -e 's/^"//' -e 's/"$//'`
for loader in $LOADERS;
do
	LOADERSDIR=$(dirname "${loader}")
	[ -d ".${LOADERSDIR}" ] || mkdir -p ".$LOADERSDIR"
	cp "$loader" ".${LOADERSDIR}" || abort "Unable to copy file"
done
echo "Loadersdir: $LOADERSDIR"
[ -d "${LOADERSDIR}" ] || abort "Cannot find gdk pixbuf loaders dir"

# Regenerate loaders.cache
export GDK_PIXBUF_MODULEDIR="${INSTBASE}${LOADERSDIR}"
export GDK_PIXBUF_MODULE_FILE="${INSTBASE}/${LOADERSDIR}/loaders.cache"
echo GDK_PIXBUF_MODULEDIR=$GDK_PIXBUF_MODULEDIR
echo GDK_PIXBUF_MODULE_FILE=$GDK_PIXBUF_MODULE_FILE
gdk-pixbuf-query-loaders --update-cache || abord "Unable to regenerate GDK puxbuf loaders cache"
unset GDK_PIXBUF_MODULEDIR
unset GDK_PIXBUF_MODULE_FILE

# Copy the Adwaita theme, from package gnome-themes-standard-data
DESTDIR=./usr/share/themes
[ -d "$DESTDIR" ] || mkdir -p "$DESTDIR"
[ -d "$DESTDIR" ] || abort "Cannot create $DESTDIR"
cp -axv /usr/share/themes/Adwaita "$DESTDIR"

# Generate APPRUNS
# No, the standard AppRun is not for us
### get_apprun
cat > AppRun <<\EOF
#!/bin/sh
HERE="$(dirname "$(readlink -f "${0}")")"
EOF
cat >> AppRun <<EOF
export GDK_PIXBUF_MODULE_FILE="\${HERE}${LOADERSDIR}/loaders.cache"
export GDK_PIXBUF_MODULEDIR="\${HERE}${LOADERSDIR}"
EOF

cat >> AppRun <<\EOF
export PATH="${HERE}"/usr/bin/:"${HERE}"/usr/sbin/:"${HERE}"/bin/:"${PATH}"
export LD_LIBRARY_PATH="${HERE}"/usr/lib/:"${HERE}"/usr/lib/i386-linux-gnu/:"${HERE}"/usr/lib/x86_64-linux-gnu/:"${HERE}"/usr/lib32/:"${HERE}"/usr/lib64/:"${HERE}"/lib/:"${HERE}"/lib/i386-linux-gnu/:"${HERE}"/lib/x86_64-linux-gnu/:"${HERE}"/lib32/:"${HERE}"/lib64/:"${LD_LIBRARY_PATH}"
export PYTHONPATH="${HERE}"/usr/share/pyshared/:"${PYTHONPATH}"
export PYTHONHOME="${HERE}"/usr/
export XDG_DATA_DIRS="${HERE}"/usr/share/:"${XDG_DATA_DIRS}"
export PERLLIB="${HERE}"/usr/share/perl5/:"${HERE}"/usr/lib/perl5/:"${PERLLIB}"
export GSETTINGS_SCHEMA_DIR="${HERE}"/usr/share/glib-2.0/schemas/:"${GSETTINGS_SCHEMA_DIR}"
export GTK_THEME=Adwaita
export GTK_PATH=${HERE}/lib/gtk-3.0
export GST_PLUGIN_SCANNER=${HERE}/libexec/gstreamer-1.0/gst-plugin-scanner
export GTK_DATA_PREFIX=${HERE}

EXEC=$(grep -e '^Exec=.*' "${HERE}"/*.desktop | head -n 1 | cut -d "=" -f 2- | sed -e 's|%.||g')
echo "----"
echo Current dir is $PWD and HERE=$HERE
cd "${HERE}/usr"
echo Current dir is now $PWD
echo executing ${EXEC}
exec ${EXEC} $@
EOF

chmod a+x AppRun

copy_deps
copy_deps

# Delete blacklisted files
BLACKLISTEDSOLIST="$SCRIPTDIR/blacklisted_so.lst"
BLACKLISTED_FILES=$(cat "$BLACKLISTEDSOLIST" | sed 's|#.*||g')
echo $BLACKLISTED_FILES
for FILE in $BLACKLISTED_FILES ; do
	FILES="$(find . -name "${FILE}" -not -path "./usr/optional/*")"
	for FOUND in $FILES ; do
		rm -vf "$FOUND" "$(readlink -f "$FOUND")"
	done
done

# Do not bundle developer stuff
rm -rf usr/include || true
rm -rf usr/lib/cmake || true
rm -rf usr/lib/pkgconfig || true
find . -name '*.la' | xargs -i rm {}

# Workaround https://github.com/AppImage/AppImageKit/issues/454
#echo "Removing libharfbuzz..."
#find usr/ -name "libharfbuzz*" -exec rm {} \;

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
XBUF_MODULE_FILE=e
