# Επιμελητής

![Home Assistant](https://img.shields.io/badge/Home_Assistant-2024.2-blue?logo=home-assistant)
![YAML](https://img.shields.io/badge/Zigbee-3.0-blue?logo=zigbee)
![Raspberry Pi](https://img.shields.io/badge/Raspberry_Pi-5-blue?logo=raspberrypi)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-blue?logo=kubernetes)
![Talos Linux](https://img.shields.io/badge/Talos_Linux-1.64-blue?logo=linux)
![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-3.19-blue?logo=alpine-linux)
![libvirt](https://img.shields.io/badge/libvirt-9.10-blue?logo=qemu)
![OpenTofu](https://img.shields.io/badge/OpenTofu-1.6-blue?logo=opentofu)
![YAML](https://img.shields.io/badge/YAML-now_30%25_more-blue?logo=yaml)

> **επιμελητής** **•** (epimelitís) _m_ (_plural_ **επιμελητές**, _feminine_ **επιμελήτρια**)
>
> one who takes care of a thing, in an official capacity; a curator, an editor, (law) a caretaker or guardian

<div align="center"/>
    <img alt="A raging raspberry carrying a shipload of lightbulbs and hardware" src="docs/images/raspberry-rage.jpg">
</div>

## What if ...

- We run **Home Assistant**
- ... but in a **Container**
- ... that runs on **Kubernetes**
- ... inside a Kernel-based **Virtual Machine**
- ... that runs on **Alpine Linux**
- ... on a **Raspberry Pi**

For this experiment I'll be using a Raspberry Pi 5 with a 256 GB class A2 microSD card (it was cheap).

Okay, hear me out:

<div align="center"/>
    <img alt="Crazy Guy suggesting Kubernetes" src="docs/images/aliens.jpg">
</div>

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [1. Setting up Alpine Linux as the Hypervisor OS](#1-setting-up-alpine-linux-as-the-hypervisor-os)
  - [Getting Alpine](#getting-alpine)
  - [Configuring Alpine](#configuring-alpine)
  - [Enable the community repository](#enable-the-community-repository)
  - [Become a Hypervisor: Installing KVM / Qemu / libvirt](#become-a-hypervisor-installing-kvm--qemu--libvirt)
  - [Enable automatic suspension and restart of Guests](#enable-automatic-suspension-and-restart-of-guests)
- [2. Provision Talos Linux](#2-provision-talos-linux)
  - [Download the `metal-arm64` image and convert it to qcow2](#download-the-metal-arm64-image-and-convert-it-to-qcow2)
  - [Run OpenTofu / Terraform to create the Talos Linux guest](#run-opentofu--terraform-to-create-the-talos-linux-guest)
  - [Connect to the Talos VM](#connect-to-the-talos-vm)
  - [Configuring and Bootstrapping Talos](#configuring-and-bootstrapping-talos)
- [3. The part where we use Kubernetes](#3-the-part-where-we-use-kubernetes)
  - [Storage, Ingress, Load balancing](#storage-ingress-load-balancing)
  - [Improved DNS](#improved-dns)
  - [Home Assistant and Sensors](#home-assistant-and-sensors)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

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

Add the network bridge:

```shell
brctl addbr brlan
brctl addif brlan eth0
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

For more information, see [Bridge] and [Bridging for Qemu] (this one is important).

[Bridge]: https://wiki.alpinelinux.org/wiki/Bridge
[Bridging for Qemu]: https://wiki.alpinelinux.org/wiki/Bridge#Bridging_for_QEMU

To restart the networking stack, run

```shell
service networking restart
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

Change into the [`infra/`](infra/) directory and run:

```shell
tofu apply
# or terraform apply
```

### Connect to the Talos VM

```shell
virsh console talos
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

**Take note of the IP**, in this case `10.22.27.56`.

You may now probably want to tell your router to always assign this IP address to that new device on your network.

### Configuring and Bootstrapping Talos

First, get `talosctl`:

```shell
curl -sL https://talos.dev/install | sh
```

Given the above IP we can now identify the available disks:

```shell
talosctl disks --insecure --nodes 10.22.27.56
```

The disk of `124 MB` is the one we just booted from, the `54 GB` is my system disk and the `107 GB` is for state.

```plain
DEV        MODEL   SERIAL   TYPE   UUID   WWID   MODALIAS                    NAME   SIZE     BUS_PATH                                         SUBSYSTEM          READ_ONLY   SYSTEM_DISK
/dev/vda   -       -        HDD    -      -      virtio:d00000002v00001AF4   -      54 GB    /pci0000:00/0000:00:01.2/0000:03:00.0/virtio2/   /sys/class/block
/dev/vdb   -       -        HDD    -      -      virtio:d00000002v00001AF4   -      107 GB   /pci0000:00/0000:00:01.3/0000:04:00.0/virtio3/   /sys/class/block
/dev/vdc   -       -        HDD    -      -      virtio:d00000002v00001AF4   -      124 MB   /pci0000:00/0000:00:01.4/0000:05:00.0/virtio4/   /sys/class/block
```

Do have a look at the [Local Path Provisioner] configuration mentioned in the Talos Linux documentation if you want to extend your storage.

Change into the [`talos/`](talos/) directory and run the `talosctl gen config` command. Make sure to use the proper disk, here `/dev/vda`:

```shell
talosctl gen config "talos-epimelitis" https://talos-epimelitis.fritz.box:6443 \
    --additional-sans=talos-epimelitis.fritz.box \
    --additional-sans=talos-epimelitis \
    --additional-sans=10.22.27.71 \
    --install-disk=/dev/vda \
    --output-dir=.talosconfig \
    --output-types=controlplane,talosconfig \
    --config-patch=@cp-patch.yaml
```

Edit the created `.talosconfig/controlplane.yaml` in an editor and add the storage volume (as shown above):

```yaml
machine:
  # ...

  kubelet:
    extraMounts:
    - destination: /var/mnt/storage
        type: bind
        source: /var/mnt/storage
        options:
        - bind
        - rshared
        - rw

  # ...

  disks:
    - device: /dev/vdb
      partitions:
        - mountpoint: /var/mnt/storage
```

<details>
<summary><b>💡 Show details ...</b></summary>

<p>On subsequent boots after the first one, <c>talosctl dmesg</c> will print something like</p>

<pre><code>
talos-epimelitis.fritz.box: user: warning: [2024-02-19T20:45:36.936258652Z]: [talos] phase udevSetup (12/17): done, 1.516129ms
talos-epimelitis.fritz.box: user: warning: [2024-02-19T20:45:36.936771652Z]: [talos] phase userDisks (13/17): 1 tasks(s)
talos-epimelitis.fritz.box: user: warning: [2024-02-19T20:45:36.937193652Z]: [talos] task mountUserDisks (1/1): starting
talos-epimelitis.fritz.box: user: warning: [2024-02-19T20:45:36.938507652Z]: [talos] task mountUserDisks (1/1): skipping setup of "/dev/vdb", found existing partitions
talos-epimelitis.fritz.box: kern:  notice: [2024-02-19T20:45:36.940458652Z]: XFS (vdb1): Mounting V5 Filesystem
talos-epimelitis.fritz.box: kern:    info: [2024-02-19T20:45:36.958119652Z]: XFS (vdb1): Ending clean mount
talos-epimelitis.fritz.box: user: warning: [2024-02-19T20:45:36.959145652Z]: [talos] task mountUserDisks (1/1): done, 21.875926ms
</code></pre>

<p>... indicating the disk has been correctly set up.</p>
</details>

Update your talosconfig with the correct endpoint:

```shell
talosctl config endpoint --talosconfig .talosconfig/talosconfig talos-epimelitis.fritz.box
```

Now apply the configuration to the node:

```shell
talosctl apply-config --insecure --nodes talos-epimelitis.fritz.box  --file .talosconfig/controlplane.yaml
```

After a while (observe the `virsh console talos` output), bootstrap etcd:

```shell
talosctl bootstrap --talosconfig .talosconfig/talosconfig --nodes talos-epimelitis.fritz.box
```

Lastly, configure your kubeconfig file:

```shell
talosctl kubeconfig --talosconfig .talosconfig/talosconfig --nodes talos-epimelitis.fritz.box
```

Switch the the new context:

```shell
kubectl config use-context admin@talos-epimelitis
```

Then apply a patch for the metric server to avoid timeout related issues:

```shell
kubectl -k metric-server
```

[Local Path Provisioner]: https://www.talos.dev/v1.6/kubernetes-guides/configuration/local-storage/#local-path-provisioner

## 3. The part where we use Kubernetes

Change into the [`cluster/`](cluster/) directory and appy the kustomizations, or:

```shell
kubectl kustomize --enable-helm cluster | kubectl apply -f -
```

Note that you'll need `kubectl kustomize` due to Helm. As of writing this, `kubectl apply -k` will not do.

### Storage, Ingress, Load balancing

The system foundation consists of these parts:

- [Local Path Provisioner] serves our `PersistentVolumeClaims` from the SD card
- [MetalLB] assignes IP addresses to Load Balancers, both in our home network and in a dedicated one.
- [Nginx Ingress Controller] handles the `Ingress` resources

With this setup we could deploy our workloads, have them persisted and make them
externally available (give or take a static route setup on your home network's Router).
When requests come in over the network bridge, MetalLB takes care of routing them
to the correct workload.

Note that by virtue of our Talos setup we already have

- [Kubelet Serving Cert Approver] for accepting certificate signing requests for system components, and
- [Kubernetes Metrics Server] for node and pod metrics.

Due to some timeout related issues the already installed Metrics Server will be
patched with a slightly more relaxed one.

[Kube Serving Cert Approver]: https://github.com/alex1989hu/kubelet-serving-cert-approver
[Kubernetes Metrics Server]: https://github.com/kubernetes-sigs/metrics-server

### Improved DNS

We can do one better:

- [Pi-Hole] is used as a DNS Server (and it _also_ filters Ads). With the power of MetalLB
  we give it an address in our home network.
- [ExternalDNS] announces Ingress host names to an external DNS - in this case, Pi-Hole.  It'll then be reachable as `http://pi-hole.home`.

With this, all we need to do is tell our Router to use our Pi-Hole as a DNS server.
Whatever Ingress we deploy now, ExternalDNS will announce it to Pi-Hole and thus
every device on our home network can access the Kubernetes-run workload by name.

### Home Assistant and Sensors

Therefore and lastly,

- [Mosquitto] is our MQTT Broker for Smart Home appliances. I re-soldered and flashed
  some Sonoff Slampher E27 sockets with Tasmota, and they'll talk to Mosquitto.
- [Home Assistant] itself. It'll be reachable as `http://home-assistant.home`.

Home Assistant is deployed using a `LoadBalancer` on the home network in order for
it to pick up UDP packets in that subnet.

[Local Path Provisioner]: https://github.com/rancher/local-path-provisioner
[MetalLB]: https://metallb.universe.tf/
[Nginx Ingress Controller]: https://github.com/kubernetes/ingress-nginx
[Pi-Hole]: https://pi-hole.net/
[ExternalDNS]: https://github.com/kubernetes-sigs/external-dns
[Mosquitto]: https://mosquitto.org/
[Home Assistant]: https://www.home-assistant.io/
