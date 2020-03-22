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

#define kUpdateInterval 0.15

static NSString *const kConnectedKey = @"connected";

static NSString *const kLogoColorKey = @"LogoColor";
static NSString *const kWheelColorKey = @"WheelColor";

typedef NS_ENUM(NSUInteger, G403LEDPosition) {
  G403LEDPositionWheel = 0,
  G403LEDPositionLogo = 1
};

@interface AppDelegate () <NSApplicationDelegate>
@property(nonatomic, weak, readwrite) IBOutlet NSWindow *window;
@property(nonatomic, weak, readwrite) IBOutlet NSColorWell *logoColorWell;
@property(nonatomic, weak, readwrite) IBOutlet NSColorWell *wheelColorWell;
@property(nonatomic, assign, readonly) BOOL connected;
@end

@implementation AppDelegate {
  IOHIDManagerRef _deviceManager;
  IOHIDDeviceRef _device;
  NSTimer *_timer;
  G403LEDPosition _lastScheduledUpdatePosition;
}

static NSColor *_Nullable G403DecodeColor(NSData *_Nullable data) {
  if (!data) {
    return nil;
  }
  return (NSColor *)[NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class]
                                                      fromData:data
                                                         error:NULL];
}

static NSData *_Nullable G403EncodeColor(NSColor *_Nullable color) {
  if (!color) {
    return nil;
  }
  return [NSKeyedArchiver archivedDataWithRootObject:color
                               requiringSecureCoding:YES
                                               error:NULL];
}

static void DeviceMatchingCallback(void *context, IOReturn result, void *sender,
                                   IOHIDDeviceRef device) {
  AppDelegate *_self = (__bridge AppDelegate *)context;
  if (!_self->_device) {
    [_self _setDevice:device];
  }
}

static void DeviceRemovalCallback(void *context, IOReturn result, void *sender,
                                  IOHIDDeviceRef device) {
  AppDelegate *_self = (__bridge AppDelegate *)context;
  if (_self->_device == device) {
    [_self _setDevice:NULL];
  }
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

  IOReturn result = IOHIDManagerOpen(_deviceManager, kIOHIDOptionsTypeNone);
  if (result != kIOReturnSuccess) {
    NSLog(@"IOHIDManagerOpen failed with error %d\n", result);
  }

  [self _loadColors];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
  return YES;
}

#pragma mark - Properties

- (BOOL)connected {
  return _device != NULL;
}

+ (BOOL)automaticallyNotifiesObserversOfConnected {
  return NO;
}

#pragma mark - Events

- (IBAction)logoColorChanged:(NSColorWell *)sender {
  [self _scheduleUpdateDeviceUsingColor:sender.color
                               position:G403LEDPositionLogo];
}

- (IBAction)wheelColorChanged:(NSColorWell *)sender {
  [self _scheduleUpdateDeviceUsingColor:sender.color
                               position:G403LEDPositionWheel];
}

#pragma mark - Private

- (void)_setDevice:(IOHIDDeviceRef _Nullable)device {
  if (device == _device) {
    return;
  }

  if (_device) {
    IOHIDDeviceUnscheduleFromRunLoop(_device, CFRunLoopGetMain(),
                                     kCFRunLoopDefaultMode);
  }

  [self willChangeValueForKey:kConnectedKey];
  _device = device;
  [self didChangeValueForKey:kConnectedKey];

  if (_device) {
    IOHIDDeviceScheduleWithRunLoop(_device, CFRunLoopGetMain(),
                                   kCFRunLoopDefaultMode);
  }
}

- (void)_scheduleUpdateDeviceUsingColor:(NSColor *)color
                               position:(G403LEDPosition)position {
  if (_timer) {
    if (_lastScheduledUpdatePosition != position) {
      [_timer fire];
    }
    [_timer invalidate];
  }

  _lastScheduledUpdatePosition = position;
  _timer = [NSTimer timerWithTimeInterval:kUpdateInterval
                                  repeats:NO
                                    block:^(NSTimer *_Nonnull timer) {
                                      [self _updateDeviceUsingColor:color
                                                           position:position];
                                      self->_timer = nil;
                                    }];

  const NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
  [runLoop addTimer:_timer forMode:NSDefaultRunLoopMode];
  [runLoop addTimer:_timer forMode:NSEventTrackingRunLoopMode];
}

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

  IOReturn result = IOHIDDeviceSetReportWithCallback(
      _device, kIOHIDReportTypeOutput, 0x11, data, sizeof(data), 1.0,
      &DeviceSetReportCallback, (__bridge void *)self);
  if (result != kIOReturnSuccess) {
    NSLog(@"IOHIDDeviceSetReportWithCallback failed with error %d\n", result);
  }

  [self _saveColors];
}

- (void)_saveColors {
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
  [userDefaults setObject:G403EncodeColor(_logoColorWell.color)
                   forKey:kLogoColorKey];
  [userDefaults setObject:G403EncodeColor(_wheelColorWell.color)
                   forKey:kWheelColorKey];
  [userDefaults synchronize];
}

- (void)_loadColors {
  NSUserDefaults *const userDefaults = [NSUserDefaults standardUserDefaults];
  [userDefaults synchronize];

  NSColor *const logoColor =
      G403DecodeColor([userDefaults dataForKey:kLogoColorKey]);
  if (logoColor) {
    _logoColorWell.color = logoColor;
  }

  NSColor *const wheelColor =
      G403DecodeColor([userDefaults dataForKey:kWheelColorKey]);
  if (wheelColor) {
    _wheelColorWell.color = wheelColor;
  }
}

@end
