#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause

# Update SSH configuration to allow root login and empty passwords
sed -i -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' "$TARGET_DIR"/etc/ssh/sshd_config
sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' "$TARGET_DIR"/etc/ssh/sshd_config

# Configure eth0 with a static IP address
cat <<EOT > "$TARGET_DIR"/etc/network/interfaces
auto eth0
iface eth0 inet static
    address 192.168.1.1
    netmask 255.255.255.0
    broadcast 192.168.1.255

auto usb0
iface usb0 inet static
    address 192.168.2.1
    netmask 255.255.255.0
    broadcast 192.168.2.255
EOT

# Enable USB Serial Console over USB-C (g_serial)
echo "g_serial" >> "$TARGET_DIR"/etc/modules

# Enable USB Ethernet Gadget
echo "g_ether" >> "$TARGET_DIR"/etc/modules

# Enable HDMI output (assumes kernel support is already configured)
# This usually requires the correct device tree and kernel modules.
echo "drm" >> "$TARGET_DIR"/etc/modules

# Ensure the system logs kernel output to the SD card
echo "dmesg > /var/log/dmesg.log" >> "$TARGET_DIR"/etc/rc.local
echo "cat /dev/ttyS2 > /var/log/uboot.log &" >> "$TARGET_DIR"/etc/rc.local
echo "echo 'Kernel and U-Boot logging enabled' >> /var/log/dmesg.log" >> "$TARGET_DIR"/etc/rc.local
