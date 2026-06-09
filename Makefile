TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

# THAY ĐỔI QUAN TRỌNG: Chuyển từ Tweak sang Application
APPLICATION_NAME = OmniGPS

OmniGPS_FILES = main.m AppDelegate.m ViewController.m
OmniGPS_FRAMEWORKS = UIKit CoreLocation UniformTypeIdentifiers
OmniGPS_CODESIGN_FLAGS = -SResources/Entitlements.plist

include $(THEOS)/makefiles/application.mk
