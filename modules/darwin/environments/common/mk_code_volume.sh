#!/usr/bin/env bash

set -e

if [ -d "$MOUNT_POINT" ]; then
  echo "Code dir exists, will not create one"
else
  DISK=$(diskutil list | grep "Macintosh HD" | awk '{print $NF;}' | awk -Fs1 '{print $1}')
  if [ -z "$DISK" ]; then
    echo "Couldn't locate primary disk"
    exit 1
  fi

  PASSPHRASE=$(security find-generic-password -s "$KEYCHAIN_ENTRY" -w 2> /dev/null || true)
  if [ -z "$PASSPHRASE" ]; then
    PASSPHRASE=$(LC_ALL=C tr -dc 'a-zA-Z0-9-_\$' < /dev/random | fold -w 24 | sed 1q)
    security add-generic-password -a $KEYCHAIN_ENTRY -s $KEYCHAIN_ENTRY -w "$PASSPHRASE"
  fi

  sudo newfs_apfs -e -A -E -S "$PASSPHRASE" -v "$VOLUME" "$DISK"
  mkdir $MOUNT_POINT
  DISK=$(diskutil list | grep "$VOLUME" | tail -1 | awk '{print $NF;}')
  if [ -z "$DISK" ]; then
    echo "Couldn't locate newly created volume"
    exit 1
  fi

  security find-generic-password -s "$KEYCHAIN_ENTRY" -w | diskutil apfs unlockVolume "$DISK" -nomount -stdinpassphrase
  diskutil mount -mountOptions $MOUNT_OPTIONS -mountPoint $MOUNT_POINT "$DISK"
  sudo chown eric:staff $MOUNT_POINT

  UUID=$(diskutil info "$DISK" | grep "Volume UUID" | awk '{print $NF;}')
  echo "UUID=$UUID $MOUNT_POINT apfs $MOUNT_OPTIONS" | sudo tee -a /etc/fstab
fi

"$FILEICON" test -q "$MOUNT_POINT" || "$FILEICON" set "$MOUNT_POINT" "$CODE_ICNS"
