#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

# Qualcomm's ABL loads U-Boot from an Android boot image. ABL looks for a
# device tree appended to the gzipped kernel, so the kernel's DTB goes after
# the compressed U-Boot rather than inside it.
gzip -n -9 -c "$BINARIES_DIR/u-boot-nodtb.bin" |
    cat - "$BINARIES_DIR/qrb2210-arduino-imola.dtb" > "$BINARIES_DIR/u-boot-nodtb.bin.gz-dtb"
"$HOST_DIR/bin/mkbootimg" \
    --kernel "$BINARIES_DIR/u-boot-nodtb.bin.gz-dtb" \
    --cmdline "root=/dev/notreal" \
    --base 0x80000000 \
    --pagesize 4096 \
    --output "$BINARIES_DIR/boot.img"

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG
