# Changelog

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
