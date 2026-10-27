# Arduino UNO Q System

This is the base Nerves System configuration for the
[Arduino UNO Q](https://docs.arduino.cc/hardware/uno-q).

| Feature        | Description                                         |
| -------------- | --------------------------------------------------- |
| CPU            | Qualcomm QRB2210, quad-core Cortex-A53              |
| Memory         | 2 GB or 4 GB LPDDR4                                 |
| Storage        | 16 GB or 32 GB eMMC                                 |
| Linux kernel   | Mainline 7.2                                        |
| Bootloader     | Arduino's U-Boot fork, loaded by Qualcomm's ABL     |
| IEx terminal   | UART `ttyMSM0`                                      |
| GPIO, I2C, SPI | Yes - [Elixir Circuits](https://github.com/elixir-circuits) |
| WiFi           | Yes - VintageNet (ath10k WCN3990)                   |
| Bluetooth      | WCN3988 (untested)                                  |
| Audio          | No - not supported by the mainline device tree      |
| Camera         | No - not supported by the mainline device tree      |

This system is a work in progress. Provisioning a board is not automated yet.

## Boot chain

Qualcomm's boot firmware (PBL, XBL, ABL) is left as Arduino ships it. ABL loads
U-Boot from the Android boot image in the `boot_a` partition. U-Boot keeps its
environment in the eMMC at 4 MiB and uses the standard Nerves A/B logic to load
the kernel and device tree from a FAT boot partition.

## eMMC layout

Partitions 1 to 66 are Qualcomm's and are never written by Nerves. The Nerves
partitions replace Arduino's `efi`, `rootfs` and `userdata` partitions at the
end of the GPT:

| Partition | Name     | Contents                         |
| --------- | -------- | -------------------------------- |
| 67        | boot_a   | FAT: `Image`, device tree        |
| 68        | boot_b   | FAT: `Image`, device tree        |
| 69        | rootfs_a | squashfs root filesystem         |
| 70        | rootfs_b | squashfs root filesystem         |
| 71        | data     | f2fs application data            |

fwup can't write a GPT with this many entries, so the partition table is
created when the board is provisioned and fwup only writes inside it. The
offsets in `fwup_include/fwup-common.conf` must match it.

The eMMC's `boot0` hardware partition holds the board's WiFi MAC address,
Bluetooth address and board revision. U-Boot reads them; nothing in Nerves
writes to `boot0`.
