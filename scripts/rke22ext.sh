#!/bin/sh

set -e

print_help() {
	local BIN_NAME=${0//*\/}
	echo "Usage: $BIN_NAME [-k \$RKE2_VER] [-a \$TARGET_ARCH] [-i \$ID] [-v \$VERSION_ID] [-r \$REPO] [-t \$TAG] [-dh]"
	echo "     -k: rke2 version to package ($RKE2_VER)"
	echo "     -a: architecture of the rke2 binary ($TARGET_ARCH)"
	echo "     -i: ID to be used for the system external image ($ID)"
	echo "     -v: VERSION_ID to be used for the system external image ($VERSION_ID)"
	echo "     -d: debug (leaves around the directories for the build process)"
	echo "     -t: tagged name to apply to the generated container image ($TAG)"
	echo "     -r: repo name to prepend to the container image ($REPO)"
	exit
}

KEEP_TMP=0
PRINTHELP=0

: ${TARGET_ARCH:="amd64"}
: ${RKE2_VER:="v1.32.1+rke2r1"}

: ${ID:="_any"}
: ${VERSION_ID:=""}
: ${EXTENSION_RELOAD_MANAGER:="1"}
: ${REPO:="localhost"}

while getopts k:a:i:v:t:r:dh opt
do
	case $opt in
	k) RKE2_VER="$OPTARG" ;;
	a) TARGET_ARCH="$OPTARG" ;;
	i) ID="$OPTARG" ;;
	v) VERSION_ID="$OPTARG" ;;
	d) KEEP_TMP=1 ;;
	t) TAG="$OPTARG" ;;
	r) REPO="$OPTARG" ;;
	?) PRINTHELP=1 ;;
	esac
done

TMPTAG1=${RKE2_VER/v}
TMPTAG1=${TMPTAG1%+*}
TMPTAG2=${RKE2_VER/*+}
TMPTAG1=${TMPTAG1}.${TMPTAG2}
: ${TAG:="sysextimg-rke2:$TMPTAG1"}

[ $PRINTHELP -eq 1 ] && print_help


: ${RKE2_DIR:="$RKE2_VER"}
: ${TEMPDIR:=$(mktemp -d -p $PWD temp-$RKE2_VER.XXXXXX)}

prereq_checks() {
	local cmd_list="tar cat chcon mksquashfs sed"
	local retval=0
	for cmd in $cmd_list; do
		if ! command -v "$cmd" > /dev/null; then
			echo "'$cmd' not found."
			retval=1
		fi
	done
	return $retval
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
	mkdir -p usr/bin
	mkdir -p usr/lib/systemd/system
	mkdir -p usr/lib/extension-release.d
	cp $TEMPDIR/bin/rke2 usr/bin/
	cp $TEMPDIR/lib/systemd/system/* usr/lib/systemd/system/

	# replace /usr/local with /usr in rke2 systemd services
	find usr/lib/systemd/system -type f -name "*.service" -print0 | xargs -0 sed -i 's/\/usr\/local\//\/usr\//g'

	cat <<EOF >usr/lib/extension-release.d/extension-release.${RKE2_DIR}
ID=${ID}
VERSION_ID=${VERSION_ID}
EXTENSION_RELOAD_MANAGER=${EXTENSION_RELOAD_MANAGER}
EOF

	chcon -R system_u:object_r:usr_t:s0 usr
	chcon -R system_u:object_r:lib_t:s0 usr/lib
	chcon -R system_u:object_r:systemd_unit_file_t:s0  usr/lib/systemd/system
	chcon -R system_u:object_r:bin_t:s0 usr/bin

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


