#!/bin/sh

: ${TARGET_ARCH:="amd64"}
: ${RKE2_VER:="v1.32.1+rke2r1"}

: ${ID:="sl-micro"}
: ${VERSION_ID:="6.1"}
: ${EXTENSION_RELOAD_MANAGER:="1"}

print_help() {
	echo "Usage: $0 [-k \$RKE2_VER] [-a \$TARGET_ARCH] [-i \$ID] [-v \$VERSION_ID] [-dh]\n"
	echo "     -k: rke2 version to package ($RKE2_VER)"
	echo "     -a: architecture of the rke2 binary ($TARGET_ARCH)"
	echo "     -i: ID to be used for the system external image ($ID)"
	echo "     -v: ID_VERSION to be used for the system external image ($ID_VERSION)"
	echo "     -d: debug (leaves around the directories for the build process)"
	exit
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
: ${RKE2_DIR:="$RKE2_VER"}

mkdir temp
pushd temp
if [ -f rke2.linux-amd64.tar.gz ]; then
	echo "RKE2 tar.gz file found under ./temp: assuming is at version $RKE2_VER"
	echo "if not please delete the rke2.linux-amd64.tar.gz file before running this script"
	read -p "press a key to continue or CTRL-c to stop."
else
	wget https://github.com/rancher/rke2/releases/download/${RKE2_VER}/rke2.linux-amd64.tar.gz
fi

tar xvf rke2.linux-amd64.tar.gz
popd

mkdir -p ${RKE2_DIR}/usr/local/bin
mkdir -p ${RKE2_DIR}/usr/lib/systemd/system
mkdir -p ${RKE2_DIR}/usr/lib/extension-release.d
cp temp/bin/rke2 ${RKE2_DIR}/usr/local/bin/
cp temp/lib/systemd/system/* ${RKE2_DIR}/usr/lib/systemd/system/

pushd $RKE2_DIR
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

mksquashfs $RKE2_DIR $RKE2_DIR.raw -all-root

if [ $KEEP_TMP = 0 ]; then
	rm -rf $RKE2_DIR temp
fi
