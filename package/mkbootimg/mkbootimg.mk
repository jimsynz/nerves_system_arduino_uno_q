################################################################################
#
# mkbootimg
#
################################################################################

MKBOOTIMG_VERSION = d2bb0af5ba6d3198a3e99529c97eda1be0b5a093
MKBOOTIMG_SITE = https://android.googlesource.com/platform/system/tools/mkbootimg
MKBOOTIMG_SITE_METHOD = git
MKBOOTIMG_LICENSE = Apache-2.0
MKBOOTIMG_LICENSE_FILES = mkbootimg.py
HOST_MKBOOTIMG_DEPENDENCIES = host-python3

define HOST_MKBOOTIMG_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/mkbootimg.py $(HOST_DIR)/share/mkbootimg/mkbootimg.py
	$(INSTALL) -D -m 0644 $(@D)/gki/generate_gki_certificate.py \
		$(HOST_DIR)/share/mkbootimg/gki/generate_gki_certificate.py
	ln -sf ../share/mkbootimg/mkbootimg.py $(HOST_DIR)/bin/mkbootimg
endef

$(eval $(host-generic-package))
