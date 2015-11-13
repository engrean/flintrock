#!/bin/bash
set -e

# Install GNU parallel.
if [ ! $(command -v parallel) ]; then
    pushd /tmp
    PARALLEL_VERSION="20151022"
    wget "http://ftpmirror.gnu.org/parallel/parallel-${PARALLEL_VERSION}.tar.bz2"
    bzip2 -dc "parallel-${PARALLEL_VERSION}.tar.bz2" | tar xvf -
    pushd "parallel-${PARALLEL_VERSION}"
    ./configure --prefix=/usr  # Amazon Linux root user doesn't have /usr/local on its $PATH
    make
    sudo make install
    popd
    rm -rf "./parallel-${PARALLEL_VERSION}*"
    popd

    # Suppress citation notice.
    echo "will cite" | parallel --bibtex
fi

###

root_device=$(
    awk -F ' ' '$1~"^/dev" && $2=="/" {print $1}' /proc/mounts)
mounted_non_root_devices=$(
    awk -F ' ' '$1~"^/dev" && $2!="/" {print $1}' /proc/mounts)

root_parent_device="${root_device%?}"

non_root_devices=$(
    lsblk --nodeps --list --noheadings --paths \
    | awk -F ' ' --assign "r=$root_parent_device" '$1!~r {print $1}')

if [ -n "$mounted_non_root_devices" ]; then
    for device in $mounted_non_root_devices; do
        sudo umount "$device"
    done
fi

if [ -n "$non_root_devices" ]; then
    echo "$non_root_devices" | parallel sudo mkfs.ext4 -F -E "lazy_itable_init=0,lazy_journal_init=0" "{}"

    mount_num=1
    for device in $non_root_devices; do
        mount_name="/mnt${mount_num}"

        sudo mkdir "$mount_name"
        sudo mount -o "defaults,noatime,nodiratime" "$device" "$mount_name"

        # Replace any existing fstab entries with our own.
        grep -v -e "^$device" /etc/fstab | sudo tee /etc/fstab
        echo "$device   $mount_name   ext4   defaults" | sudo tee -a /etc/fstab

        mount_num=$((mount_num + 1))
    done
fi
