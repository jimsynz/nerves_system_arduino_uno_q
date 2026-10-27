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
| USB            | Ethernet gadget (`usb0`) for `mix upload`           |
| GPIO, I2C, SPI | Yes - [Elixir Circuits](https://github.com/elixir-circuits) |
| WiFi           | Yes - VintageNet (ath10k WCN3990)                   |
| Bluetooth      | WCN3988, `hci0` comes up (otherwise untested)       |
| MCU            | STM32U585 via `arduino-router` and `unoq-mcu`       |
| Audio          | No - not supported by the mainline device tree      |
| Camera         | No - not supported by the mainline device tree      |

This system is a work in progress. Provisioning a board is not automated yet.

## Boot chain

Qualcomm's boot firmware (PBL, XBL, ABL) is left as Arduino ships it. ABL loads
U-Boot from the Android boot image in the `boot_a` partition. U-Boot keeps its
environment in the eMMC at 4 MiB and uses the standard Nerves A/B logic to load
the kernel and device tree from a FAT boot partition. U-Boot also adds the
board's WiFi MAC and Bluetooth addresses to the device tree.

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

## WiFi and the modem

The WiFi firmware runs on the QRB2210's modem remote processor. Before the
modem can boot it needs two helpers from
[linux-msm](https://github.com/linux-msm): `rmtfs`, which serves the modem's
storage partitions (read-only) and then starts the modem, and `tqftpserv`,
which serves it the WiFi firmware. `/usr/sbin/uno-q-init` starts both from
erlinit's `--pre-run-exec`, before the Erlang VM starts, and restarts them if
they exit. `wlan0` appears about 13 seconds after power on.

## The STM32U585 MCU

`uno-q-init` also runs Arduino's
[arduino-router](https://github.com/arduino/arduino-router), the MsgPack-RPC
link to the MCU over `/dev/ttyHS1`, as Arduino's Debian image does. Programs
talk to the MCU through `/var/run/arduino-router.sock`. When the router is
ready it raises GPIO 70, which tells the MCU that Linux is up.

The MCU is flashed over SWD, bit-banged from the QRB2210's GPIOs by OpenOCD.
`unoq-mcu` wraps the common operations:

```sh
unoq-mcu animation                      # install the Nerves boot animation
unoq-mcu sketch loader.elf sketch.bin   # flash a loader and sketch
unoq-mcu dump /tmp/mcu.bin              # read the MCU's flash
unoq-mcu reset
```

The MCU's loader plays a boot animation on the LED matrix until GPIO 70 goes
high. `unoq-mcu animation` replaces Arduino's animation with a Nerves logo.
