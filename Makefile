ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
DEB_ARCH = iphoneos-arm64e
INSTALL_TARGET_PROCESSES = MobileSafari

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChatGPTSafariFullscreen
ChatGPTSafariFullscreen_FILES = Tweak.xm
ChatGPTSafariFullscreen_CFLAGS = -fobjc-arc -Wall -Wextra
ChatGPTSafariFullscreen_FRAMEWORKS = UIKit WebKit

include $(THEOS_MAKE_PATH)/tweak.mk

before-package::
	@echo "Building ChatGPTSafariFullscreen for RootHide"
