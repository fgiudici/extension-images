#!/bin/sh

OUTPUT_DIR="artifacts"
CONF_IMG="ignition.img"
TMP_BUTANE_CONFIG="config.bu"
TMP_IGNITION_CONFIG="config.ign"
TMP_COMBUSTION_SCRIPT="script"

# you can set your custom vars permanently in $HOME/.uc-sysext/config
: ${ENVC:="$HOME/.uc-sysext/config"}
if [ "$ENVC" != "skip" -a -f "$ENVC" ]; then
  . "$ENVC"
fi


: ${MICRO_OS:=slmicro}
: ${CFG_ROOT_PWD:="uc"}
: ${CFG_SSH_KEY:=""}
: ${CFG_HOSTNAME:="$MICRO_OS"}
: ${VM_STORE:="/var/lib/libvirt/images"}
: ${VM_DISKSIZE:="30"}
: ${VM_MEMORY:="4096"}
: ${VM_NETWORK:="network=default"}
: ${VM_CORES:="2"}
: ${VM_GRAPHICS:="spice"}
: ${VM_AUTOCONSOLE:="text"}
: ${RANCHER_PWD:="uc"}
: ${RANCHER_VER:=""}
: ${RANCHER_REPO:="latest"}
: ${RANCHER_HOSTNAME:=""}
: ${REMOTE_KVM:=""}
: ${RKE2IMAGE:="quay.io/fgiudici/sysextimg-rke2:1.30.9.rke2r1"}

case "$MICRO_OS" in
  leapmicro)
    DISTRO_NAME="openSUSE-Leap-Micro.x86_64-Default-qcow"
    DISTRO_URL_BASE="https://download.opensuse.org/distribution/leap-micro/6.0/appliances/"
    ;;
  microOS|microos)
    DISTRO_NAME="openSUSE-MicroOS.x86_64-ContainerHost-kvm-and-xen"
    DISTRO_URL_BASE="https://download.opensuse.org/tumbleweed/appliances/"
    ;;
  slmicro)
    DISTRO_NAME="SL-Micro.x86_64-6.1-Base-qcow-GM"
    ;;
  *)
    echo ERR: parameter \"$MICRO_OS\" is not a valid OS
    exit -1
    ;;
esac

VM_DISKSIZE="${VM_DISKSIZE}G"
QEMU_IMG="${DISTRO_NAME}.qcow2"
LOOPDEV=""

error() {
  msg="${1}"
  echo ERR: ${msg:-"command failed"}

  ignition_volume_prep_cleanup
  exit -1
}

check_rke2_image_exists() {
  podman pull $RKE2IMAGE
  if [ $? -neq 0 ]; then
    error "RKE2 image $RKE2IMAGE doesn't exists"
  fi
}

write_ignition() {
  ROOT_HASHED_PWD=$(openssl passwd -6 "$CFG_ROOT_PWD") || error

  cat << EOF
variant: fcos
version: 1.3.0

passwd:
    users:
      - name: root
        password_hash: "$ROOT_HASHED_PWD"
storage:
  files:
    - path: /etc/hostname
      contents:
        inline: "$CFG_HOSTNAME"
      mode: 0644
      overwrite: true
EOF

  if [ -n "$CFG_SSH_KEY" ]; then
    cat << EOF
    - path: /root/.ssh/authorized_keys
      contents:
        inline: "$CFG_SSH_KEY"
      mode: 0600
      overwrite: true
EOF
  fi
}

write_combustion() {
  cat << EOF
#!/bin/sh
# combustion: network

cat <<- END > /etc/systemd/system/ensure-sysext.service
[Unit]
BindsTo=systemd-sysext.service
After=systemd-sysext.service
DefaultDependencies=no
# Keep in sync with systemd-sysext.service
ConditionDirectoryNotEmpty=|/etc/extensions
ConditionDirectoryNotEmpty=|/run/extensions
ConditionDirectoryNotEmpty=|/var/lib/extensions
ConditionDirectoryNotEmpty=|/usr/local/lib/extensions
ConditionDirectoryNotEmpty=|/usr/lib/extensions
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/systemctl daemon-reload
ExecStart=/usr/bin/systemctl restart --no-block sockets.target timers.target multi-user.target
[Install]
WantedBy=sysinit.target
END

mkdir /etc/extensions
podman pull $RKE2IMAGE
mnt=\$(podman image mount $RKE2IMAGE)
cp \$mnt/*.raw /etc/extensions/

systemctl enable systemd-sysext
systemctl enable ensure-sysext
ln -s /usr/lib/systemd/system/rke2-server.service /etc/systemd/system/multi-user.target.wants/rke2-server.service

echo "Configured with Combustion" > /etc/issue.d/combustion
EOF
}

create_config_files() {
  write_ignition > "$TMP_BUTANE_CONFIG"
  write_combustion > "$TMP_COMBUSTION_SCRIPT"
}

ignition_volume_prep() {
  local lodevs

  echo "* build ignition/combustion config image volume"
  # 1000Kb disk img
  dd if=/dev/zero of="$CONF_IMG" count=2000 || error

  sudo losetup -f "$CONF_IMG" || error
  lodevs=$(sudo losetup -j "$CONF_IMG") || error

  LOOPDEV=$(echo $lodevs | cut -d ":" -f 1 | head -n 1)
  [ -z "$LOOPDEV" ] && error "cannot find loop device"

  sudo mkfs.ext4 $LOOPDEV
  sudo e2label $LOOPDEV ignition

  mkdir tmpmount
  sudo mount $LOOPDEV tmpmount

  write_ignition > "$TMP_BUTANE_CONFIG"
  [ -f "$TMP_BUTANE_CONFIG" ] || error
  butane --strict --pretty "$TMP_BUTANE_CONFIG" > "$TMP_IGNITION_CONFIG" || error

  write_combustion > "$TMP_COMBUSTION_SCRIPT"
  [ -f "$TMP_COMBUSTION_SCRIPT" ] || error

  sudo mkdir tmpmount/ignition || error
  sudo cp -a "$TMP_IGNITION_CONFIG" tmpmount/ignition/ || error
  sudo mkdir tmpmount/combustion || error
  sudo cp -a "$TMP_COMBUSTION_SCRIPT" tmpmount/combustion/ || error

  ignition_volume_prep_cleanup
  mv "$CONF_IMG" "$OUTPUT_DIR/"
}

ignition_volume_prep_cleanup() {
  if [ -d tmpmount ]; then
    sudo umount tmpmount
    sudo rmdir tmpmount
  fi
  if [ -n "$LOOPDEV" ]; then
    sudo losetup --detach $LOOPDEV
    LOOPDEV=""
  fi
  if [ -f ""$TMP_IGNITION_CONFIG"" ]; then
    rm "$TMP_IGNITION_CONFIG"
  fi
}

qcow_prep() {
  if [ ! -f "$QEMU_IMG" ]; then
    if [ -n "$DISTRO_URL_BASE" ]; then
      wget "${DISTRO_URL_BASE}/${QEMU_IMG}" || error
    else
      error "$QEMU_IMG not found (download it first)"
    fi
  fi
  cp "${QEMU_IMG}" "${OUTPUT_DIR}/${QEMU_IMG}"
  qemu-img resize "${OUTPUT_DIR}/${QEMU_IMG}" "$VM_DISKSIZE"
  echo "* qcow image ready: $QEMU_IMG"
}

create_vm() {
  local uuid=$(uuidgen) || error
  local vmdisk="${uuid}-${MICRO_OS}.qcow2"
  local vmconf="${uuid}-${MICRO_OS}-config.img"
  local remote_option=""

  if [ -z "$REMOTE_KVM" ]; then
    sudo cp -a "${OUTPUT_DIR}/${QEMU_IMG}" "${VM_STORE}/${vmdisk}" || error
    sudo cp -a "${OUTPUT_DIR}/${CONF_IMG}" "${VM_STORE}/${vmconf}" || error
  else
    scp "${OUTPUT_DIR}/${QEMU_IMG}" "root@${REMOTE_KVM}:${VM_STORE}/${vmdisk}" || error
    scp "${OUTPUT_DIR}/${CONF_IMG}" "root@${REMOTE_KVM}:${VM_STORE}/${vmconf}" || error
    remote_option="--connect=qemu+ssh://root@${REMOTE_KVM}/system"
  fi

  sudo virt-install $remote_option \
    -n "${MICRO_OS}-$uuid" --osinfo=slem5.4 --memory="$VM_MEMORY" --vcpus="$VM_CORES" \
    --disk path="${VM_STORE}/${vmdisk}",bus=virtio --import \
    --disk path="${VM_STORE}/${vmconf}" \
    --graphics "$VM_GRAPHICS" \
    --network "$VM_NETWORK" \
    --autoconsole "$VM_AUTOCONSOLE" $VM_CUSTOMOPTION
}

get_kubeconfig() {
  local ip="$1"
  local FILE="rke2.yaml"

  scp root@$ip:/etc/rancher/k3s/k3s.yaml ./ > /dev/null 
  if [ $? -eq 0 ]; then
    FILE="k3s.yaml"
  else
    cp root@$ip:/etc/rancher/rke2/rke2.yaml ./ > /dev/null || error
  fi
  sed -i "s/127.0.0.1/${ip}/g" $FILE.yaml || error
  chmod 600 $FILE.yaml || error
  echo "DONE: $FILE.yaml retrieved successfully"
  echo "      you may want to:"
  echo "export KUBECONFIG=$PWD/$FILE.yaml"
}

deploy_rancher() {
  local ip=$(kubectl get nodes -o=jsonpath='{.items[0].metadata.annotations.k3s\.io/internal-ip}') || error
  [ -z "$ip" ] && error "cannot retrieve cluster node ip"

  echo "* add helm repos"
  helm repo add rancher-latest https://releases.rancher.com/server-charts/latest || error
  helm repo add jetstack https://charts.jetstack.io || error
  helm repo update || error

  echo "* deploy cert-manager"
  kubectl create namespace cattle-system

  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml || error

  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.1 || error

  echo "* deploy rancher"
  # For Kubernetes v1.25 or later, set global.cattle.psp.enabled to false.
  local rancherOpts="--namespace cattle-system"
  if [ -n "$RANCHER_VER" ]; then
    case $RANCHER_VER in
      "Dev"|"dev"|"Devel"|"devel")
        rancherOpts="$rancherOpts --devel"
        ;;
      *)
        rancherOpts="$rancherOpts --version $RANCHER_VER"
	;;
    esac
  fi

  if [ "$RANCHER_HOSTNAME" = "" ]; then
    RANCHER_HOSTNAME="${ip}.sslip.io"
  fi

  helm install rancher rancher-${RANCHER_REPO}/rancher \
  $rancherOpts \
  --set hostname=${RANCHER_HOSTNAME} \
  --set replicas=1 \
  --set bootstrapPassword="$RANCHER_PWD" || error

  echo "Rancher URL: https://$RANCHER_HOSTNAME"
}

help() {
  local BIN_NAME=${0//*\/}
  cat << EOF
Usage:
  $BIN_NAME CMD

  list of commands (CMD):
    artifacts             # creates a qcow2 image and ignite/combustion config volume (ignite.img)
                          # if config files are not found generates them first
    config                # creates ignite (ignite.fcc) and combustion ("$TMP_COMBUSTION_SCRIPT") config files
    create                # creates a VM from disks created by "artifacts", with VM_MEMORY VM_CORES
                          # if the artifacts folder is not found, calls "artifacts" first
    delete [all]          # delete the generated artifacts; with 'all' deletes also config files
    getkubeconf <IP>      # get the kubeconfig file from a k3s/rke2 host identified by the <IP> ip address
    deployrancher         # install Rancher via Helm chart (requires helm binary already installed)

  supported env vars:
    ENVC                # the environment config file to be imported if present (default: '\$HOME/.uc-sysext/config)
                        # set to 'skip' to skip importing env variable declarations from any file
    MICRO_OS            # OS to install: 'leapmicro', 'microOS' or 'slmicro' (current: '$MICRO_OS')
    CFG_HOSTNAME        # provisioned hostname (current: '$CFG_HOSTNAME')
    CFG_SSH_KEY         # the authorized ssh public key for remote access
    CFG_ROOT_PWD        # the root password of the installed system (current: '$CFG_ROOT_PWD')
    RKE2IMAGE           # container with systemd-sysext extension image (current: '$RKE2IMAGE')
    REMOTE_KVM          # the hostname/ip address of the KVM host if not using the local one (requires root access)
    VM_AUTOCONSOLE      # auto start console for the micro OS VM (current: '$VM_AUTOCONSOLE')
    VM_CORES            # number of vcpus assigned to the VM (current: '$VM_CORES')
    VM_DISKSIZE         # desired storage size in GB of the VM (current: '$VM_DISKSIZE')
    VM_GRAPHICS         # graphical display configuration for the VM (current: '$VM_GRAPHICS')
    VM_MEMORY           # amount of RAM assigned to the VM in MiB (current: '$VM_MEMORY')
    VM_NETWORK          # virtual network (current: '$VM_NETWORK')
    VM_STORE            # path where to put the disks for the VM (current: '$VM_STORE')
    VM_CUSTOMOPTION     # custom option appended to 'virt-install'

  env vars for day 2 Rancher installation
    RANCHER_PWD         # the admin password for rancher deployment (current: '$RANCER_PWD')
    RANCHER_VER         # Rancher version to install (default picks up the latest stable)
    RANCHER_REPO        # Rancher helm chart repo to pick rancher from (current '$RANCHER_REPO')
    RANCHER_HOSTNAME    # Rancher hostname (default '\$IP.sslip.io')

example:
  VM_STORE=/data/images/ VM_NETWORK="network=\$NETNAME,mac=52:54:00:00:01:fe" VM_MEMORY=8192 VM_CORES=4 $BIN_NAME create
  VM_STORE=/data/images/ VM_NETWORK="bridge=br-dmz,mac=52:54:00:00:01:fe" VM_MEMORY=8192 VM_CORES=4 $BIN_NAME create
  VM_STORE=/data/images/ VM_NETWORK="bridge=br-dmz,mac=52:54:00:00:01:fe" VM_MEMORY=8192 VM_CORES=4 $BIN_NAME create VM_CUSTOMOPTION="--network bridge=br-lan,mac=52:54:00:10:22"

  $BIN_NAME getkubeconf 192.168.122.2


EOF

  exit 0
}

case ${1} in

  artifacts)
    sudo echo ""
    if [ ! -d "$OUTPUT_DIR" ]; then
      mkdir "$OUTPUT_DIR" || error
    fi

    qcow_prep
    check_rke2_image_exists
    ignition_volume_prep
    ;;

  config)
    create_config_files
    ;;

  create)
    sudo echo ""
    if [ ! -d "$OUTPUT_DIR" ]; then
      mkdir "$OUTPUT_DIR" || error
    fi

    [ ! -f "$OUTPUT_DIR/$QEMU_IMG" ] && qcow_prep
    if [ ! -f "$OUTPUT_DIR/$CONF_IMG" ]; then
      check_rke2_image_exists
      ignition_volume_prep
    else
      echo "WARNING: found '$OUTPUT_DIR/$CONF_IMG', skip rebuild of ignition/combustion volume"
    fi

    create_vm
    rm -rf "$OUTPUT_DIR" "$TMP_BUTANE_CONFIG" "$TMP_COMBUSTION_SCRIPT"
    ;;

  delete)
    rm -rf "$OUTPUT_DIR"
    if [ "${2}" = "all" ]; then
      rm -rf "$TMP_BUTANE_CONFIG" "$TMP_COMBUSTION_SCRIPT"
    fi
    ;;

  getkubeconf|getk)
    IP=${2}
    if [ -z "$IP" ]; then
      error "ip address required but missing"
    fi
    get_kubeconfig "$IP"
    ;;

  deployrancher|rancher)
    deploy_rancher
    ;;

  *)
    help
    ;;

esac
