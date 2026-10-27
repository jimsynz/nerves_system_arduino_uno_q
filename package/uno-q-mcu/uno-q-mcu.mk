################################################################################
#
# uno-q-mcu
#
################################################################################

UNO_Q_MCU_SOURCE =
UNO_Q_MCU_LICENSE = Apache-2.0
UNO_Q_MCU_DEPENDENCIES = host-python3

define UNO_Q_MCU_BUILD_CMDS
	$(HOST_DIR)/bin/python3 -I $(UNO_Q_MCU_PKGDIR)/make_nerves_anim.py \
		$(@D)/nerves-bootanimation.bin
endef

define UNO_Q_MCU_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/nerves-bootanimation.bin \
		$(TARGET_DIR)/usr/share/uno-q-mcu/nerves-bootanimation.bin
	$(INSTALL) -D -m 0755 $(UNO_Q_MCU_PKGDIR)/unoq-mcu \
		$(TARGET_DIR)/usr/bin/unoq-mcu
endef

$(eval $(generic-package))
