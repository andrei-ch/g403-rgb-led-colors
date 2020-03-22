//
//  AppDelegate.m
//  G403
//
//  Created by Andrei Chtcherbatchenko on 3/21/20.
//  Copyright © 2020 Andrei Chtcherbatchenko. All rights reserved.
//

#import "AppDelegate.h"
#import <IOKit/hid/IOHIDManager.h>

#define kLogitechVendorID 0x46d
#define kG403ProductID 0xc08f

static NSString *const kDeviceConnectedKey = @"deviceConnected";

typedef NS_ENUM(NSUInteger, G403LEDPosition) {
  G403LEDPositionWheel = 0,
  G403LEDPositionLogo = 1
};

@interface AppDelegate ()
@property(nonatomic, weak, readwrite) IBOutlet NSWindow *window;
@property(nonatomic, assign, readwrite) IOHIDDeviceRef device;
@property(nonatomic, assign, readonly) BOOL deviceConnected;
@end

@implementation AppDelegate {
  IOHIDManagerRef _deviceManager;
  IOHIDDeviceRef _device;
}

@synthesize device = _device;

static void DeviceMatchingCallback(void *context, IOReturn result, void *sender,
                                   IOHIDDeviceRef IOHIDDeviceRef) {
  AppDelegate *_self = (__bridge AppDelegate *)context;
  if (_self->_device) {
    return;
  }
  _self.device = IOHIDDeviceRef;
  IOHIDDeviceScheduleWithRunLoop(_self->_device, CFRunLoopGetMain(),
                                 kCFRunLoopDefaultMode);
}

static void DeviceRemovalCallback(void *context, IOReturn result, void *sender,
                                  IOHIDDeviceRef IOHIDDeviceRef) {
  AppDelegate *_self = (__bridge AppDelegate *)context;
  if (_self->_device != IOHIDDeviceRef) {
    return;
  }
  IOHIDDeviceUnscheduleFromRunLoop(_self->_device, CFRunLoopGetMain(),
                                   kCFRunLoopDefaultMode);
  _self.device = NULL;
}

static void DeviceSetReportCallback(void *_Nullable context, IOReturn result,
                                    void *_Nullable sender,
                                    IOHIDReportType type, uint32_t reportID,
                                    uint8_t *report, CFIndex reportLength) {}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  _deviceManager =
      IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);

  IOHIDManagerSetDeviceMatching(_deviceManager, (__bridge CFDictionaryRef) @{
    @"VendorID" : @(kLogitechVendorID),
    @"ProductID" : @(kG403ProductID),
    @"PrimaryUsage" : @6,
  });

  IOHIDManagerRegisterDeviceMatchingCallback(
      _deviceManager, &DeviceMatchingCallback, (__bridge void *)self);

  IOHIDManagerRegisterDeviceRemovalCallback(
      _deviceManager, &DeviceRemovalCallback, (__bridge void *)self);

  IOHIDManagerScheduleWithRunLoop(_deviceManager, CFRunLoopGetMain(),
                                  kCFRunLoopDefaultMode);

  IOHIDManagerOpen(_deviceManager, kIOHIDOptionsTypeNone);
}

#pragma mark - Properties

- (IOHIDDeviceRef)device {
  return _device;
}

- (void)setDevice:(IOHIDDeviceRef)device {
  if (device == _device) {
    return;
  }
  [self willChangeValueForKey:kDeviceConnectedKey];
  _device = device;
  [self didChangeValueForKey:kDeviceConnectedKey];
}

- (BOOL)deviceConnected {
  return _device != NULL;
}

+ (BOOL)automaticallyNotifiesObserversOfDeviceConnected {
  return NO;
}

#pragma mark - Events

- (IBAction)logoColorChanged:(NSColorWell *)sender {
  [self _updateDeviceUsingColor:sender.color position:G403LEDPositionLogo];
}

- (IBAction)wheelColorChanged:(NSColorWell *)sender {
  [self _updateDeviceUsingColor:sender.color position:G403LEDPositionWheel];
}

#pragma mark - Private

- (void)_updateDeviceUsingColor:(NSColor *)color
                       position:(G403LEDPosition)position {
  if (!_device) {
    return;
  }

  const unsigned char target = (unsigned char)position;
  const unsigned char red = (unsigned char)round([color redComponent] * 255.f);
  const unsigned char green =
      (unsigned char)round([color greenComponent] * 255.f);
  const unsigned char blue =
      (unsigned char)round([color blueComponent] * 255.f);

  const unsigned char data[20] = {0x11,  0xff, 0x0e, 0x3b, target, 0x01, red,
                                  green, blue, 0x00, 0x00, 0x00,   0x00, 0x00,
                                  0x00,  0x00, 0x00, 0x00, 0x00,   0x00};

  IOHIDDeviceSetReportWithCallback(_device, kIOHIDReportTypeOutput, 0x11, data,
                                   sizeof(data), 1.0, &DeviceSetReportCallback,
                                   (__bridge void *)self);
}

@end
