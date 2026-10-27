################################################################################
#
# arduino-router
#
################################################################################

ARDUINO_ROUTER_VERSION = 0.11.0
ARDUINO_ROUTER_SITE = $(call github,arduino,arduino-router,v$(ARDUINO_ROUTER_VERSION))
ARDUINO_ROUTER_LICENSE = GPL-3.0-or-later
ARDUINO_ROUTER_LICENSE_FILES = LICENSE.txt
ARDUINO_ROUTER_LDFLAGS = -X main.Version=$(ARDUINO_ROUTER_VERSION)

$(eval $(golang-package))
