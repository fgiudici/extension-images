# extension-images
This repo contains a couple of scripts to DEMO a RKE2 single node cluster deployment on a VM
using an immutable OS base image, choosen among:
* OpenSUSE Leap Micro
* OpenSUSE MicroOS
* SUSE SL Micro

and a RKE2 systemd-sysext system extension image, retrieved from a container package.

## quickstart

>[!NOTE]
>This quickstart assumes you have `qemu`, `virt-install`, `podman`, `butane` binaries available in your
>path and may assume commands available in common linux installations, otherwise the script will fail.

It uses an already built RKE2 extension image put in a container at
**quay.io/fgiudici/sysextimg-rke2:1.30.9.rke2r1** (used by default).

To start a OpenSUSE Leap Micro VM with RKE2 installed from an extension image just do:
```bash
export CFG_SSH_KEY="$YOUR_SSH_KEY"

scripts/micro-rke2-vm.sh create
```
Wait the provisioning to complete, till you see the `Configured with Combustion` output.

Example:
```
$> export CFG_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOG9ZB9bqE+qpKM8FErVtg6VszRQe4nB3HoHK+bdaE9e"
$> scripts/micro-rke2-vm.sh create
[sudo] password for user: 

HTTP response 302  [https://download.opensuse.org/distribution/leap-micro/6.0/appliances//openSUSE-Leap-MiAdding URL: https://opensuse.mirror.garr.it/mirrors/opensuse/distribution/leap-micro/6.0/appliances/openSUSaving 'openSUSE-Leap-Micro.x86_64-Default-qcow.qcow2'
HTTP response 200  [https://opensuse.mirror.garr.it/mirrors/opensuse/distribution/leap-micro/6.0/applianceopenSUSE-Leap-Micro. 100% [=======================================================>]    1.21G  111.73MB/s
                          [Files: 1  Bytes: 1.21G [103.74MB/s] Redirects: 1  Todo: ]
qemu-img: Use the --shrink option to perform a shrink operation.
qemu-img: warning: Shrinking an image will delete all data beyond the shrunken image's end. Before performing such an operation, make sure there is no important data there.
* qcow image ready: openSUSE-Leap-Micro.x86_64-Default-qcow.qcow2
Trying to pull quay.io/fgiudici/sysextimg-rke2:1.30.9.rke2r1...
Getting image source signatures
Copying blob 3588bde06ad2 skipped: already exists  
Copying config 8a238e4327 done   | 
Writing manifest to image destination
8a238e4327b49302c64fa3befd60309064286a4cea4ee062fb6d67b54309d97d
scripts/micro-rke2-vm.sh: line 62: [: -neq: binary operator expected
* build ignition/combustion config image volume
2000+0 records in
2000+0 records out
1024000 bytes (1.0 MB, 1000 KiB) copied, 0.00477955 s, 214 MB/s
mke2fs 1.47.1 (20-May-2024)

Filesystem too small for a journal
Discarding device blocks: done                            
Creating filesystem with 1000 1k blocks and 128 inodes

Allocating group tables: done                            
Writing inode tables: done                            
Writing superblocks and filesystem accounting information: done


Starting install...
Creating domain...                                                                 |         00:00:00     
Running text console command: virsh --connect qemu:///system console leapmicro-82651e56-d55d-4d46-a51b-3077a992ff1e
Connected to domain 'leapmicro-82651e56-d55d-4d46-a51b-3077a992ff1e'
Escape character is ^] (Ctrl + ])


Welcome to openSUSE Leap Micro 6.0  (x86_64) - Kernel 6.4.0-17-default (ttyS0).

SSH host key: SHA256:wSeKb6ioyRESh0dR9pdDI5UixWJWQNkpr4iSpUA6IIc (RSA)
SSH host key: SHA256:b2mwdcWT4fTwe+GcGm/5vHjVb1Xod9EPkvwPWIm+LUs (ECDSA)
SSH host key: SHA256:xVeBPrbStVhEnsyJaLuZK2MzAsDId1iNwISrAW71q0g (ED25519)
eth0: 192.168.124.179 fe80::5054:ff:fec8:1e55


Configured with Combustion
Activate the web console with: systemctl enable --now cockpit.socket

leapmicro login: 

```
logout from the console (CTRL + ]) and retrieve the kubeconfig file:

```
scripts/micro-rke2-vm.sh getk 192.168.124.179
```

>[!NOTE]
>In the command above you have to change the IP from `192.168.124.179` to what you get for eth0,
>check your own output!

Now you can enjoy your RKE2 cluster:
```
export KUBECONFIG=$(pwd)/rke2.yaml

kubeconfig get nodes
```

## Build the RKE2 extension image
You can build the RKE2 extension image from the official RKE2 tarball release with the `rke22ext.sh` script:
```
scripts/rke22ext.sh
```
>[!TIP]
>The rke22ext.sh script will retrieve the `rke2:1.32.1.rke2r1` RKE2 binaries by default.
>
>Specify you own version with the `-k` flag or get all the available options with the `-h` flag.

You will get the extension image file in the current dir (e.g., `v1.32.1+rke2r1.raw`) and a container is built
for you locally (`localhost/sysextimg-rke2`) having the tag equal to the RKE2 version built (e.g., `localhost/sysextimg-rke2:1.32.1.rke2r1`).

Once you push the build container to your own registry you can use it with the `micro-rke2-vm.sh create` command by exporting the RKE2IMAGE=${YOUR_CONTAINER_IMAGE}.

>[!TIP]
>execute `micro-rke2-vm.sh` with no arguments to get the help with all possible customizations.