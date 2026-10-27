################################################################################
#
# uno-q-firmware
#
################################################################################

# Installs a subset of Buildroot's linux-firmware. linux-firmware's own
# options don't cover the QCM2290/QRB2210 files.
UNO_Q_FIRMWARE_SOURCE =
UNO_Q_FIRMWARE_DEPENDENCIES = linux-firmware
UNO_Q_FIRMWARE_LICENSE = linux-firmware (see the linux-firmware package)

UNO_Q_FIRMWARE_FILES = \
	ath10k/WCN3990/hw1.0/board-2.bin \
	ath10k/WCN3990/hw1.0/qcm2290/firmware-5.bin \
	ath10k/WCN3990/hw1.0/qcm2290/wlanmdsp.mbn \
	qca/apbtfw11.tlv \
	qca/apnv11.bin \
	qcom/a702_sqe.fw \
	qcom/qcm2290/a702_zap.mbn \
	qcom/qcm2290/adsp.mbn \
	qcom/qcm2290/modem.mbn

define UNO_Q_FIRMWARE_INSTALL_TARGET_CMDS
	$(foreach f,$(UNO_Q_FIRMWARE_FILES),\
		$(INSTALL) -D -m 0644 $(LINUX_FIRMWARE_DIR)/$(f) \
			$(TARGET_DIR)/lib/firmware/$(f)$(sep))
	ln -sf ../../ath10k/WCN3990/hw1.0/qcm2290/wlanmdsp.mbn \
		$(TARGET_DIR)/lib/firmware/qcom/qcm2290/wlanmdsp.mbn
endef

$(eval $(generic-package))
