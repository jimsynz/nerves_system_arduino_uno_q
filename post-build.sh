#!/bin/sh

set -e

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p $TARGET_DIR/usr/share/fwup
$HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR

# tqftpserv keeps its state in /var/lib/tqftpserv, but the root filesystem is
# read-only. The link is made here rather than in rootfs_overlay because Hex
# packages can't contain absolute symlinks.
ln -sfn /tmp/tqftpserv $TARGET_DIR/var/lib/tqftpserv
