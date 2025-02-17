#!/bin/sh

set -e

print_help() {
	echo "Usage: $0 [-k \$RKE2_VER] [-a \$TARGET_ARCH] [-i \$ID] [-v \$VERSION_ID] [-t \$TAG] [-dh]"
	echo "     -k: rke2 version to package ($RKE2_VER)"
	echo "     -a: architecture of the rke2 binary ($TARGET_ARCH)"
	echo "     -i: ID to be used for the system external image ($ID)"
	echo "     -v: ID_VERSION to be used for the system external image ($ID_VERSION)"
	echo "     -d: debug (leaves around the directories for the build process)"
	echo "     -t: tagged name to apply to the generated container image"
	echo "     -r: repo name to prepend to the container image"
	exit
}

REPO="localhost"
KEEP_TMP=0
while getopts k:a:i:v:t:r:dh opt
do
	case $opt in
	k) RKE2_VER="$OPTARG" ;;
	a) TARGET_ARCH="$OPTARG" ;;
	i) ID="$OPTARG" ;;
	v) VERSION_ID= ;;
	d) KEEP_TMP=1 ;;
	t) TAG="$OPTARG" ;;
	r) REPO="$OPTARG" ;;
	?) print_help ;;
	esac
done

: ${TARGET_ARCH:="amd64"}
: ${RKE2_VER:="v1.32.1+rke2r1"}

: ${ID:="sl-micro"}
: ${VERSION_ID:="6.1"}
: ${EXTENSION_RELOAD_MANAGER:="1"}

TMPTAG1=${RKE2_VER/v}
TMPTAG1=${TMPTAG1%+*}
TMPTAG2=${RKE2_VER/*+}
TMPTAG1=${TMPTAG1}.${TMPTAG2}
: ${TAG:="sysextimg-rke2:$TMPTAG1"}

: ${RKE2_DIR:="$RKE2_VER"}
: ${TEMPDIR:=$(mktemp -d -p $PWD temp-$RKE2_VER.XXXXXX)}

prereq_checks() {
	local cmd_list="tar cat chcon mksquashfs"
	for cmd in $cmd_list; do
		if ! command -v "$cmd" > /dev/null; then
			echo "'$cmd' not found."
			return 1
		fi
	done
}

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

	cat <<EOF >usr/lib/extension-release.d/extension-release.${RKE2_DIR}
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

create_container_image() {
	printf "FROM scratch\nADD ${RKE2_DIR}.raw /\n" > Dockerfile
	podman build . -t $REPO/$TAG
}

prereq_checks
get_rke2_archive
make_rke2_squashfs
create_container_image

if [ $KEEP_TMP = 0 ]; then
	rm -rf  $TEMPDIR Dockerfile
fi


