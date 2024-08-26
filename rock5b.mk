COMPILE_NS_USER ?= 64
override COMPILE_NS_KERNEL := 64
COMPILE_S_USER ?= 64
COMPILE_S_KERNEL ?= 64

include common.mk

DEBUG ?= 1

# Do not leave a partially downloaded binary in case wget fails midway
.DELETE_ON_ERROR:

################################################################################
# Paths to git projects and various binaries
################################################################################
TF_A_PATH		?= $(ROOT)/trusted-firmware-a
BINARIES_PATH		?= $(ROOT)/out
UBOOT_PATH		?= $(ROOT)/u-boot
UBOOT_BIN		?= $(UBOOT_PATH)/u-boot.bin
ROOT_IMG 		?= $(ROOT)/out-br/images/rootfs.ext2
BOOT_IMG		?= $(ROOT)/out/rock5b.img
RKDEVELOPTOOL_PATH	?= $(ROOT)/rkdeveloptool
RKDEVELOPTOOL_BIN	?= $(RKDEVELOPTOOL_PATH)/rkdeveloptool
LOADER_BIN		?= $(BINARIES_PATH)/rk3588_spl_loader_v1.15.113.bin
TPL_BIN		        ?= $(BINARIES_PATH)/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin

LINUX_MODULES ?= y

BR2_TARGET_ROOTFS_CPIO = n
BR2_TARGET_ROOTFS_CPIO_GZIP = n
BR2_TARGET_ROOTFS_EXT2 = y
BR2_TARGET_GENERIC_GETTY_PORT = ttyS2
ifeq ($(LINUX_MODULES),y)
# If modules are installed...
# ...enable automatic device detection and driver loading
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV = y
# ...and configure eth0 automatically based on ifup helpers
BR2_PACKAGE_IFUPDOWN_SCRIPTS = y
# BR2_SYSTEM_DHCP = eth0
# An image with module takes more space
BR2_TARGET_ROOTFS_EXT2_SIZE = 640M
# Enable SSH daemon for remote login
BR2_PACKAGE_OPENSSH = y
BR2_PACKAGE_OPENSSH_SERVER = y
BR2_ROOTFS_POST_BUILD_SCRIPT = $(ROOT)/build/br-ext/board/rock5b/post-build.sh
else
BR2_TARGET_ROOTFS_EXT2_SIZE = 112M
endif

################################################################################
# Targets
################################################################################

all: boot-img

clean: buildroot-clean

include toolchain.mk

################################################################################
# Arm Trusted Firmware-A
################################################################################
TF_A_EXPORTS ?= CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		M0_CROSS_COMPILE="$(CCACHE)$(AARCH32_CROSS_COMPILE)"

TF_A_DEBUG ?= $(DEBUG)
ifeq ($(TF_A_DEBUG),0)
TF_A_LOGLVL ?= 30
TF_A_OUT = $(TF_A_PATH)/build/rk3588/release
else
TF_A_LOGLVL ?= 40
TF_A_OUT = $(TF_A_PATH)/build/rk3588/debug
endif

TF_A_FLAGS ?= ARCH=aarch64 PLAT=rk3588 SPD=opteed DEBUG=$(TF_A_DEBUG) \
	      LOG_LEVEL=$(TF_A_LOGLVL)

.PHONY: tfa
tfa:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) bl31

.PHONY: tfa-clean
tfa-clean:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) clean

clean: tfa-clean

################################################################################
# U-Boot
################################################################################
UBOOT_DEFCONFIG_FILES := $(UBOOT_PATH)/configs/nanopc-t6-rk3588_defconfig \
			 $(ROOT)/build/kconfigs/u-boot_rock5b.conf

UBOOT_FLAGS ?= CROSS_COMPILE=$(CROSS_COMPILE_NS_KERNEL) \
	       CC=$(CROSS_COMPILE_NS_KERNEL)gcc \
	       HOSTCC="$(CCACHE) gcc"

$(TPL_BIN):
	mkdir -p $(BINARIES_PATH)
	cd $(BINARIES_PATH) && \
		wget -O $(notdir $(TPL_BIN)) https://github.com/rockchip-linux/rkbin/raw/master/bin/rk35/$(notdir $(TPL_BIN))

UBOOT_EXPORTS ?= BL31=$(TF_A_OUT)/bl31/bl31.elf TEE=$(OPTEE_OS_BIN) ROCKCHIP_TPL=$(TPL_BIN)

u-boot-defconfig: $(UBOOT_PATH)/.config

$(UBOOT_PATH)/.config: $(UBOOT_DEFCONFIG_FILES)
	cd $(UBOOT_PATH) && \
                scripts/kconfig/merge_config.sh $(UBOOT_DEFCONFIG_FILES)

.PHONY: u-boot-defconfig

.PHONY: u-boot
u-boot: $(TPL_BIN) $(UBOOT_PATH)/.config optee-os tfa
	$(UBOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) $(UBOOT_FLAGS)

.PHONY: u-boot-clean
u-boot-clean:
	$(UBOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) $(UBOOT_FLAGS) distclean

clean: u-boot-clean

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH ?= arm64
LINUX_DEFCONFIG_COMMON_FILES ?= $(LINUX_PATH)/arch/arm64/configs/defconfig \
				$(CURDIR)/kconfigs/rock5b.conf

.PHONY: linux-defconfig
linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm64
LINUX_COMMON_TARGETS += Image rockchip/rk3588-nanopc-t6.dtb \
			$(if $(filter y,$(LINUX_MODULES)),modules)

.PHONY: linux
linux: linux-common
ifeq ($(LINUX_MODULES),y)
	$(MAKE) -C $(LINUX_PATH) ARCH=arm64 modules_install \
		INSTALL_MOD_PATH=$(BINARIES_PATH)/modules
endif

$(LINUX_PATH)/arch/arm64/boot/Image.gz: linux
	gzip -c $(LINUX_PATH)/arch/arm64/boot/Image >$@

.PHONY: linux-defconfig-clean
linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm64

.PHONY: linux-clean
linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm64

.PHONY: linux-cleaner
linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_PLATFORM = rockchip-rk3588
OPTEE_OS_COMMON_FLAGS += CFG_ENABLE_EMBEDDED_TESTS=y

.PHONY: optee-os
optee-os: optee-os-common

.PHONY: optee-os-clean
optee-os-clean: optee-os-clean-common

clean: optee-os-clean

################################################################################
# Boot image, shall be copied to SD card
################################################################################

# U-Boot offset comes from CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR=0x4000
# Partition no. 5 ends at 12288 + BR2_TARGET_ROOTFS_EXT2_SIZE (in kiB)
# File size needs to be slightly bigger to accomodate for whatever meta-data
rootfs-size-kib := $(shell echo $(BR2_TARGET_ROOTFS_EXT2_SIZE) | sed 's/M/*1024/')
p5-end-kib := $(shell echo $$((12288 + $(rootfs-size-kib))))
img-size-kib := $(shell echo $$(($(p5-end-kib) + 1024)))

.PHONY: boot-img
boot-img: u-boot buildroot $(LINUX_PATH)/arch/arm64/boot/Image.gz
	mkdir -p $(BINARIES_PATH)
	rm -f $(BOOT_IMG)
	truncate -s $(img-size-kib)KiB $(BOOT_IMG)
	parted -s $(BOOT_IMG) \
		unit kiB \
		mklabel gpt \
		mkpart idbloader 32 4032 \
		mkpart primary fat32 4032 4096 \
		mkpart primary fat32 4096 8192 \
		mkpart uboot 8192 12288 \
		mkpart root fat32 12288 $(p5-end-kib)
	sgdisk -u 5:17d61bff-8fdc-4089-b675-9be21b9f6ac7 $(BOOT_IMG)
	dd if=$(UBOOT_PATH)/idbloader.img of=$(BOOT_IMG) bs=1kiB seek=32 conv=notrunc
	dd if=$(UBOOT_PATH)/u-boot.itb of=$(BOOT_IMG) bs=1kiB seek=8192 conv=notrunc
	e2mkdir $(ROOT_IMG):/boot
	e2cp $(LINUX_PATH)/arch/arm64/boot/Image.gz $(ROOT_IMG):/boot
	e2cp $(LINUX_PATH)/arch/arm64/boot/dts/rockchip/rk3588-nanopc-t6.dtb $(ROOT_IMG):/boot
ifeq ($(LINUX_MODULES),y)
	find $(BINARIES_PATH)/modules -type f | while read f; do e2cp -a $$f $(ROOT_IMG):$$(echo $$f | sed s@$(BINARIES_PATH)/modules@@); done
endif
	dd if=$(ROOT_IMG) of=$(BOOT_IMG) bs=1kiB seek=12288 conv=notrunc

.PHONY: boot-img-clean
boot-img-clean:
	rm -f $(BOOT_IMG)

clean: boot-img-clean

################################################################################
# rkdeveloptool
################################################################################

$(RKDEVELOPTOOL_PATH)/Makefile:
	cd $(RKDEVELOPTOOL_PATH) && \
		autoreconf -i && \
		./configure CXXFLAGS=-Wno-format-truncation

$(RKDEVELOPTOOL_BIN): $(RKDEVELOPTOOL_PATH)/Makefile
	$(MAKE) -C $(RKDEVELOPTOOL_PATH)

rkdeveloptool: $(RKDEVELOPTOOL_BIN)

rkdeveloptool-clean:
	$(MAKE) -C $(RKDEVELOPTOOL_PATH) clean

rkdeveloptool-distclean:
	$(MAKE) -C $(RKDEVELOPTOOL_PATH) clean

clean: rkdeveloptool-clean

$(LOADER_BIN):
	mkdir -p $(BINARIES_PATH)
	cd $(BINARIES_PATH) && \
		wget https://dl.radxa.com/rock5/sw/images/loader/rock-5b/release/$(notdir $(LOADER_BIN))

################################################################################
# Flash the image via USB onto the onboard eMMC
################################################################################

define flash-help
        @echo
        @echo "Please connect the board to the computer via a USB A-C cable."
        @echo "The cable should be connected to the Type-C port on the NanoPC T6."
        @echo "Remove the microSD card and power cable from the board."
        @echo "Press and hold the Maskrom (MASK) button."
        @echo "While holding the MASK button, insert the power cable."
        @echo "This should normally put the device into Maskrom mode."
        @echo "(For more details, visit: https://wiki.friendlyelec.com/wiki/index.php/NanoPC-T6)"
        @echo
        @read -r -p "Press enter to continue, Ctrl-C to cancel:" dummy
endef

flash: $(BOOT_IMG) $(LOADER_BIN) $(RKDEVELOPTOOL_BIN)
	$(call flash-help)
	$(RKDEVELOPTOOL_BIN) db $(LOADER_BIN)
	sleep 1
	$(RKDEVELOPTOOL_BIN) wl 0 $(BOOT_IMG)

nuke-emmc: $(LOADER_BIN) $(RKDEVELOPTOOL_BIN)
	@echo
	@echo "** WARNING: this command will make the onboard eMMC unbootable!"
	@echo "It can be used to boot from the SD card again."
	$(call flash-help)
	dd if=/dev/zero of=$(BINARIES_PATH)/zero.img bs=1M count=64
	$(RKDEVELOPTOOL_BIN) db $(LOADER_BIN)
	sleep 1
	$(RKDEVELOPTOOL_BIN) wl 0 $(BINARIES_PATH)/zero.img
