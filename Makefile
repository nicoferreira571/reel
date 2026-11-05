ARCHS = armv7
TARGET = iphone:clang:11.4:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Reel
Reel_FILES = main.m
Reel_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation MediaPlayer CoreMedia
Reel_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk
