#!/usr/bin/env bash

set -e

as_user() {
  launchctl asuser "$(id -u "$OWNER")" sudo -H -u "$OWNER" "$@"
}

if [ -d "$MOUNT_POINT" ]; then
  echo "Code dir exists, will not create one"
else
  CONTAINER=$(diskutil info -plist / | plutil -extract APFSContainerReference raw -)
  if [ -z "$CONTAINER" ]; then
    echo "Couldn't locate primary APFS container"
    exit 1
  fi

  PASSPHRASE=$(as_user security find-generic-password -s "$KEYCHAIN_ENTRY" -w 2> /dev/null || true)
  if [ -z "$PASSPHRASE" ]; then
    PASSPHRASE=$(LC_ALL=C tr -dc 'a-zA-Z0-9-_\$' < /dev/random | fold -w 24 | sed 1q)
    as_user security add-generic-password -a "$KEYCHAIN_ENTRY" -s "$KEYCHAIN_ENTRY" -w "$PASSPHRASE"
  fi

  newfs_apfs -e -A -E -S "$PASSPHRASE" -v "$VOLUME" "$CONTAINER"
  mkdir "$MOUNT_POINT"
  DISK=$(diskutil list "$CONTAINER" | grep -w "$VOLUME" | tail -1 | awk '{print $NF;}')
  if [ -z "$DISK" ]; then
    echo "Couldn't locate newly created volume"
    exit 1
  fi

  echo "$PASSPHRASE" | diskutil apfs unlockVolume "$DISK" -nomount -stdinpassphrase
  diskutil mount -mountOptions "$MOUNT_OPTIONS" -mountPoint "$MOUNT_POINT" "$DISK"
  chown "$OWNER:staff" "$MOUNT_POINT"

  UUID=$(diskutil info "$DISK" | grep "Volume UUID" | awk '{print $NF;}')
  echo "UUID=$UUID $MOUNT_POINT apfs $MOUNT_OPTIONS" >> /etc/fstab
fi

as_user "$FILEICON" test -q "$MOUNT_POINT" || as_user "$FILEICON" set "$MOUNT_POINT" "$CODE_ICNS"
