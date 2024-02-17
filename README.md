# Επιμελητής

> **επιμελητής** **•** (epimelitís) _m_ (_plural_ **επιμελητές**, _feminine_ **επιμελήτρια**)
>
> one who takes care of a thing, in an official capacity; a curator, an editor, (law) a caretaker or guardian

For this experiment I'll be using a Raspberry Pi 5
with a 256 GB microSD card (class A2).

## 1. Setting up Alpine Linux as the Hypervisor OS

### Getting Alpine

Get Alpine Linux from the [Downloads](https://www.alpinelinux.org/downloads/) page and select the Raspberry Pi variant.

For example, Alpine Linux 3.19.1 for Raspberry Pi can be downloaded from:

```shell
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-rpi-3.19.1-aarch64.img.gz
```

Flash the image using [Raspberry Pi Imager] and boot your
Pi from the SD card.

### Configuring Alpine

I had to plug in my keyboard to the first USB 3 port _after_ the Pi was booted.
Other ports or timings didn't work for me.

Following the [setup-alpine] instructions,

- log in as `root` with no password
- run `setup-alpine` and answer truthfully
    - disable remote login for root
    - create a new user for yourself
    - enable lan and wifi
    - enable SSH server
    - create a `sys` partition
- reboot
- log in and run `ip a` to get the Pi's IP address

From your regular machine, run `ssh-copy-id <USER>@<IP>`.
If this works you can unplug the display and keyboard.

See also [Granting Your User Administrative Access] for
`doas` (`sudo` in Ubuntu lingo). As `root`, run

```
apk add doas
echo 'permit :wheel' > /etc/doas.d/doas.conf
addgroup <USER> wheel
```

After this, `doas <command>` does the trick.

[setup-alpine]: https://docs.alpinelinux.org/user-handbook/0.1a/Installing/setup_alpine.html
[Granting Your User Administrative Access]: https://docs.alpinelinux.org/user-handbook/0.1a/Working/post-install.html#_granting_your_user_administrative_access

### Enable the community repository

Edit the `/etc/apk/repositories` file:

```shell
doas apk add vim
doas vim /etc/apk/repositories
```

Enable the `http://alpine.sakamoto.pl/alpine/v3.19/community` rpo.

### Become a Hypervisor: Installing KVM / Qemu / libvirt

```shell
apk add \
    libvirt-daemon libvirt-client \
    qemu-img qemu-system-arm qemu-system-aarch64 qemu-modules \
    openrc
rc-update add libvirtd
```

Add your user to `libvirt`:

```shell
addgroup <USER> libvirt
```

> By default, libvirt uses NAT for VM connectivity. If you want to use the default configuration, you need to load the `tun` module.

```shell
modprobe tun
echo "tun" >> /etc/modules-load.d/tun.conf
cat /etc/modules | grep tun || echo tun >> /etc/modules
```

> If you prefer bridging a guest over your Ethernet interface, you need to make a bridge.

Add the scripts that will create bridges off `/etc/network/interfaces`:

```shell
apk add bridge
```

Change your `/etc/network/interfaces` to

- disable `dhcp` on your `eth0`
- add `iface brlan inet dhcp`
- set `bridge-ports eth0` to bridge it with eth0

```plain
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual

auto brlan
iface brlan inet dhcp
    bridge-ports eth0
    bridge-stp 0
    post-up ip -6 a flush dev brlan; sysctl -w net.ipv6.conf.brlan.disable_ipv6=1

auto wlan0
iface wlan0 inet dhcp
```

For more information, see [Bridge].

[Bridge]: https://wiki.alpinelinux.org/wiki/Bridge

To restart the networking stack, run

```shell
service network restart
```

If it fails, reconnect your keyboard ...

> In order to use libvirtd to remotely control KVM over ssh PolicyKit needs a `.pkla` informing it that this is allowed. Write the following file to `/etc/polkit-1/localauthority/50-local.d/50-libvirt-ssh-remote-access-policy.pkla`

```shell
apk add dbus polkit
rc-update add dbus
```

We do that:

```shell
mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat <<EOF > file.txt
[Remote libvirt SSH access]
 Identity=unix-group:libvirt
 Action=org.libvirt.unix.manage
 ResultAny=yes
 ResultInactive=yes
 ResultActive=yes
EOF
```

For the Terraform `libvirt` provider to work, we also need
to enable TCP forwarding for the SSH server.

```shell
sed -i '/^AllowTcpForwarding no$/s/no/yes/' /etc/ssh/sshd_config
service sshd restart
```

### Enable automatic suspension and restart of Guests

> The `libvirt-guests` service (available from Alpine 3.13.5)
> allows running guests to be automatically suspended or shut
> down when the host is shut down or rebooted.
>
> The service is configured in /etc/conf.d/libvirt-guests.
> Enable the service with:

```shell
rc-update add libvirt-guests
```

## 2. Provision Talos Linux

### Download the `metal-arm64` image and convert it to qcow2

```shell
curl -LO https://github.com/siderolabs/talos/releases/download/v1.6.4/metal-arm64.iso
qemu-img convert -O qcow2 metal-arm64.iso metal-arm64.qcow2
```

### Run OpenTofu / Terraform to create the Talos Linux guest

```shell
tofu apply
```

### Connect to the Talos VM

```shell
virsh connect talos
```

In the UEFI shell, type `exit`. You will be brought to the
UEFI, where you select the `Boot Manager`. Pick the third
disk from the list and boot from there - you'll see Talos Linux' boot menu now:

```
                GNU GRUB  version 2.06

 /------------------------------------------------\
 |*Talos ISO                                      |
 | Reset Talos installation                       |
 |                                                |
 \------------------------------------------------/
```

Boot Talos. Say hi. It'll greet you with

```plain
[    9.851478] [talos] entering maintenance service {"component": "controller-runtime", "controller": "config.AcquireController"}
[    9.854129] [talos] this machine is reachable at: {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.855517] [talos]  10.22.27.56 {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.856546] [talos]  2001:9e8:17ba:2200:5054:ff:feba:99ef {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.858176] [talos] server certificate issued {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController", "fingerprint": "rMWhs9V9Y30sbs9W5KNCgVRReKGrfvV0FwMtqEX4OW8="}
[    9.860209] [talos] upload configuration using talosctl: {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.862119] [talos]  talosctl apply-config --insecure --nodes 10.22.27.56 --file <config.yaml> {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.863452] [talos] or apply configuration using talosctl interactive installer: {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.864784] [talos]  talosctl apply-config --insecure --nodes 10.22.27.56 --mode=interactive {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.866219] [talos] optionally with node fingerprint check: {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
[    9.867265] [talos]  talosctl apply-config --insecure --nodes 10.22.27.56 --cert-fingerprint 'rMWhs9V9Y30sbs9W5KNCgVRReKGrfvV0FwMtqEX4OW8=' --file <config.yaml> {"component": "controller-runtime", "controller": "runtime.MaintenanceServiceController"}
```

You may now probably want to tell your router to always assign
this IP address to that new device on your network.

## 3. Getting `talosctl`

```shell
curl -sL https://talos.dev/install | sh
```

## 100. Setting up Talos Linux

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
