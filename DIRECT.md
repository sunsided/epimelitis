# Direct installation of Talos Linux on Raspberry Pi

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Setting up Talos Linux](#setting-up-talos-linux)
  - [Updating the EEPROM](#updating-the-eeprom)
  - [Downloading the Talos Linux image](#downloading-the-talos-linux-image)
  - [Writing the Talos Linux image to the SD card](#writing-the-talos-linux-image-to-the-sd-card)
  - [Fixing `boot.txt`](#fixing-boottxt)
  - [Bootstrapping the Node](#bootstrapping-the-node)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Setting up Talos Linux

From [Talos Linux Guides / Installation / Single Board Computers / Raspberry Pi Series]:

### Updating the EEPROM

> Use [Raspberry Pi Imager] to write an EEPROM update image to a spare SD card.

You can download and install the Imager using this command:

```shell
curl -XGET -L https://downloads.raspberrypi.org/imager/imager_latest_amd64.deb -o /tmp/imager_latest_amd64.deb
sudo dpkg -i /tmp/imager_latest_amd64.deb
```

I used Raspberry Pi Imager 1.8.5.

> Select Misc utility images under the Operating System tab.

- For `Raspberry Pi Device`, select Raspberry Pi 5.
- For `Operating System`, select _Misc utility images_ > _Bootloader (Pi 5 family)_ > _USB Boot_.
This way if things go sideways you can still boot from USB
without having to fiddle with the SD card.
- For `Storage`, select _Generic- SD/MMC/MS PRO_ or whatever resembles your SD card. If it doesn't show up, remove and add it back it. Do not unmount it.
- Click `Next` and follow through.

> Remove the SD card from your local machine and insert it into the Raspberry
> Pi. Power the Raspberry Pi on, and wait at least 10 seconds. If successful,
> the green LED light will blink rapidly (forever), otherwise an error pattern
> will be displayed. If an HDMI display is attached to the port closest to the
> power/USB-C port, the screen will display green for success or red if a
> failure occurs. Power off the Raspberry Pi and remove the SD card from it.

- The LED will first turn green, then flash red, then turn green.
- After some seconds, it starts to flash and the HDMI output turns green.
- Turn off the Raspberry Pi.
- Remove the SD card.

[Raspberry Pi Imager]: https://www.raspberrypi.com/software/
[Talos Linux Guides / Installation / Single Board Computers / Raspberry Pi Series]: https://www.talos.dev/v1.6/talos-guides/install/single-board-computers/rpi_generic/

### Downloading the Talos Linux image

At the time of writing this, Talos Linux [v1.6.4] was the latst release.

[v1.6.4]: https://github.com/siderolabs/talos/releases/tag/v1.6.4

However, Talos Linux [v1.6.4] does not support Raspberry Pi 5.
After booting from its image, the Pi gives this:

```log
Device-tree file "bcm2712-rpi-5-b.dtb" not found

The installed operating system (OS) does not indicate support for Raspberry Pi 5
Update the OS or set os_check=0 in config.txt to skip this check.
```

Instead, we will go with [v1.7.0-alpha.0]. Who doesn't like a good pre-release.

[v1.7.0-alpha.0]: https://github.com/siderolabs/talos/releases/tag/v1.7.0-alpha.0

Download the `metal-rpi_generic-arm64` image and unpack it:


```shell
curl -LO https://github.com/siderolabs/talos/releases/download/v1.7.0-alpha.0/metal-rpi_generic-arm64.raw.xz
xz -dk metal-rpi_generic-arm64.raw.xz
```

The [v1.6.4] image is about 1.3 GB in size (after unpacking).

### Writing the Talos Linux image to the SD card

The Talos documentation mentions the use of `/dev/mmcblk0`, however
using a microSD to SD adapter, the card showed up as `/dev/sda` for me (as my main drive is on `/dev/nvme0n1`).

YMMV! Do check with `lsblock` and look for a drive of the currect size.

```text
sda                       8:0    1 238,3G  0 disk
└─sda1                    8:1    1   256M  0 part  /media/user/848A-864E
nvme0n1                 259:0    0   3,6T  0 disk
├─nvme0n1p1             259:1    0     1G  0 part  /boot
├─nvme0n1p2             259:2    0   512M  0 part  /boot/efi
└─nvme0n1p3             259:3    0   3,6T  0 part
```

Double-check with `lsblk` after unplugging.

```shell
sudo dd if=metal-rpi_generic-arm64.raw of=/dev/mmcblk0 conv=fsync bs=4M status=progress
```

☕ This takes a bit. Go grab a beverage of your liking. Stay hydrated.

### Fixing `boot.txt`

Unplug and replug the SD card and mount the EFI partition.
In my case, this is `/dev/sda1` as identfied as `vfat   FAT32 EFI` by `fdisk -f`:

```text
sdb
├─sdb1
│    vfat   FAT32 EFI   BC40-EF66                                37,9M    62%
├─sdb2
│
├─sdb3
│    xfs          BOOT  2db5c4ca-f185-4380-ae7f-fea16071f15e    777,2M    17%
├─sdb4
│
├─sdb5
│
└─sdb6
```

As root, mount the EFI partition to a directory:

```shell
sudo mount -t fat32 /dev/sdb1 /mnt
```

In there you will find `config.txt`; for me, it looked like
this:

```ini
# See https://www.raspberrypi.com/documentation/computers/configuration.html
# Reduce GPU memory to give more to CPU.
gpu_mem=32
# Enable maximum compatibility on both HDMI ports;
# only the one closest to the power/USB-C port will work in practice.
hdmi_safe:0=1
hdmi_safe:1=1
# Load U-Boot.
kernel=u-boot.bin
# Forces the kernel loading system to assume a 64-bit kernel.
arm_64bit=1
# Run as fast as firmware / board allows.
arm_boost=1
# Enable the primary/console UART.
enable_uart=1
# Disable Bluetooth.
dtoverlay=disable-bt
# Disable Wireless Lan.
```

### Bootstrapping the Node

> Insert the SD card to your board, turn it on and wait for
> the console to show you the instructions for bootstrapping
> the node. Following the instructions in the console output
> to connect to the interactive installer:
