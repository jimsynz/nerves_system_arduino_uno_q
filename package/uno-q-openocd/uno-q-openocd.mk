################################################################################
#
# uno-q-openocd
#
################################################################################

UNO_Q_OPENOCD_VERSION = cb0c224e936091156ecf3025ba05657408ed64c8
UNO_Q_OPENOCD_SITE = https://git.code.sf.net/p/openocd/code
UNO_Q_OPENOCD_SITE_METHOD = git
UNO_Q_OPENOCD_GIT_SUBMODULES = YES
UNO_Q_OPENOCD_LICENSE = GPL-2.0-or-later
UNO_Q_OPENOCD_LICENSE_FILES = COPYING LICENSES/preferred/GPL-2.0
UNO_Q_OPENOCD_AUTORECONF = YES
UNO_Q_OPENOCD_DEPENDENCIES = host-pkgconf libgpiod2

# The bundled jimtcl must be built static; Buildroot's default --enable-shared
# would reach its configure too.
UNO_Q_OPENOCD_CONF_OPTS = \
	--disable-shared \
	--enable-static \
	--enable-linuxgpiod \
	--enable-internal-jimtcl \
	--disable-internal-libjaylink \
	--disable-jlink \
	--disable-werror \
	--disable-doxygen-html \
	--disable-doxygen-pdf

define UNO_Q_OPENOCD_INSTALL_BOARD_CONFIG
	$(INSTALL) -D -m 0644 $(UNO_Q_OPENOCD_PKGDIR)/arduino_uno_q.cfg \
		$(TARGET_DIR)/usr/share/openocd/scripts/board/arduino_uno_q.cfg
endef
UNO_Q_OPENOCD_POST_INSTALL_TARGET_HOOKS += UNO_Q_OPENOCD_INSTALL_BOARD_CONFIG

$(eval $(autotools-package))
