#!/bin/sh

set -e

: ${TARGET_ARCH:="amd64"}
: ${RKE2_VER:="v1.32.1+rke2r1"}

: ${ID:="sl-micro"}
: ${VERSION_ID:="6.1"}
: ${EXTENSION_RELOAD_MANAGER:="1"}

: ${RKE2_DIR:="$RKE2_VER"}
: ${TEMPDIR:=$(mktemp -d -p $PWD temp-$RKE2_VER.XXXXXX)}

print_help() {
	echo "Usage: $0 [-k \$RKE2_VER] [-a \$TARGET_ARCH] [-i \$ID] [-v \$VERSION_ID] [-dh]\n"
	echo "     -k: rke2 version to package ($RKE2_VER)"
	echo "     -a: architecture of the rke2 binary ($TARGET_ARCH)"
	echo "     -i: ID to be used for the system external image ($ID)"
	echo "     -v: ID_VERSION to be used for the system external image ($ID_VERSION)"
	echo "     -d: debug (leaves around the directories for the build process)"
	exit
}

prereq_checks() {
	local cmd_list="tar chcon mksquashfs"
	for cmd in $cmd_list; do
		if ! command -v "$cmd" > /dev/null; then
			echo "'$cmd' not found."
			return 1
		fi
	done
}

KEEP_TMP=0
while getopts k:t:i:v:dh opt
do
	case $opt in
	k) RKE2_VER="$OPTARG" ;;
	t) TARGET_ARCH="$OPTARG" ;;
	i) ID="$OPTARG" ;;
	v) VERSION_ID= ;;
	d) KEEP_TMP=1 ;;
	?) print_help ;;
	esac
done

get_rke2_archive() {
	pushd ${TEMPDIR}
	if [ -f rke2.linux-amd64.tar.gz ]; then
		echo "RKE2 tar.gz file found under $TEMPDIR: assuming is at version $RKE2_VER"
		read -p "press a key to continue or CTRL-c to stop."
	else
		wget https://github.com/rancher/rke2/releases/download/${RKE2_VER}/rke2.linux-amd64.tar.gz
	fi

	tar xvf rke2.linux-amd64.tar.gz
	popd
}

make_rke2_squashfs() {
	pushd ${TEMPDIR}
	mkdir ${RKE2_DIR}
	pushd ${RKE2_DIR}
	mkdir -p usr/local/bin
	mkdir -p usr/lib/systemd/system
	mkdir -p usr/lib/extension-release.d
	cp $TEMPDIR/bin/rke2 usr/local/bin/
	cp $TEMPDIR/lib/systemd/system/* usr/lib/systemd/system/

	/bin/cat <<EOF >usr/lib/extension-release.d/extension-release.${RKE2_DIR}
ID=${ID}
VERSION_ID=${VERSION_ID}
EXTENSION_RELOAD_MANAGER=${EXTENSION_RELOAD_MANAGER}
EOF

	chcon -R system_u:object_r:usr_t:s0 usr
	chcon -R system_u:object_r:lib_t:s0 usr/lib
	chcon -R system_u:object_r:systemd_unit_file_t:s0  usr/lib/systemd/system
	chcon -R system_u:object_r:bin_t:s0 usr/local/bin

	popd

	rm -f $RKE2_DIR.raw
	mksquashfs $RKE2_DIR $RKE2_DIR.raw -all-root

	popd
	mv $TEMPDIR/$RKE2_DIR.raw ./
}

prereq_checks
get_rke2_archive
make_rke2_squashfs

if [ $KEEP_TMP = 0 ]; then
	rm -rf  $TEMPDIR
fi


