################################################################################
#
# tqftpserv
#
################################################################################

TQFTPSERV_VERSION = 1.3
TQFTPSERV_SITE = $(call github,linux-msm,tqftpserv,v$(TQFTPSERV_VERSION))
TQFTPSERV_LICENSE = BSD-3-Clause
TQFTPSERV_LICENSE_FILES = LICENSE
TQFTPSERV_DEPENDENCIES = qrtr

$(eval $(meson-package))
