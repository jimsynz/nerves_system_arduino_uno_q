# Changelog

## v0.1.3

* Enable policy routing in the kernel. VintageNet gives each interface its
  own routing table, so without it installing routes failed with
  "RTNETLINK answers: Operation not supported" and WiFi kept reconnecting

## v0.1.2

* Enable the pattern, oneshot and activity LED triggers, which the official
  Nerves systems also enable. Without the pattern trigger, Delux fails to
  start, and so does Nerves Livebook

## v0.1.1

* `mix firmware.qdl` downloads Arduino's prebuilt `qdl` if it isn't on your
  `PATH`, so you only need `fwup` installed
* The README explains adding the system to a project and provisioning a board
  step by step, with a udev rule that also keeps ModemManager away from the
  board in EDL mode, and troubleshooting tips
* The Hex package metadata lists Apache-2.0, which covers the Elixir code and
  the MCU tooling

## v0.1.0

The first release of the rebuilt Arduino UNO Q system, based on mainline
Linux 7.2, Arduino's U-Boot fork, `nerves_system_br` 1.35.3 and the 15.3
Nerves toolchain.

* `mix firmware.qdl` installs Nerves on a board over USB using Qualcomm EDL
  mode, whatever is on its eMMC
* Standard Nerves A/B firmware updates, including `mix upload` over the USB
  Ethernet gadget
* WiFi through VintageNet. The system starts `rmtfs` and `tqftpserv`, which
  the modem needs before the WiFi firmware can run
* `arduino-router` for MsgPack-RPC with the STM32U585 MCU, started at boot
  the way Arduino's Debian image does
* `unoq-mcu` and OpenOCD for flashing the MCU over SWD from Linux
* A Nerves logo boot animation for the MCU's LED matrix

Audio, the camera, the video codec and GPU userspace aren't supported yet.
See the README for details.
