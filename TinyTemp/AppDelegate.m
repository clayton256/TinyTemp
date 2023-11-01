//
//  AppDelegate.m
//  TinyTemp
//
//  Created by Udo Thiel on 28.10.23.
//

#import "AppDelegate.h"
#import "IOHID/IOHID.h"
#import <ServiceManagement/ServiceManagement.h>

@interface AppDelegate () <NSMenuDelegate>
@property IBOutlet NSMenu *statusItemMenu;
@property IBOutlet NSMenu *allTempsMenu;
@property IBOutlet NSMenuItem *lal;
@property (readonly) NSStatusItem * _Nonnull statusItem;
@end

@implementation AppDelegate {
	IOHID *iohid;
	NSTimer *timer_cpu, *timer_ssd, *timer_batt, *timer_all;
	double temp_cpu, temp_ssd, temp_batt;
	NSString *thermalState;
}

- (void)awakeFromNib {
	// NSStatusItem
	_statusItem							= [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
	_statusItem.behavior				= NSStatusItemBehaviorTerminationOnRemoval;
	_statusItem.button.imagePosition	= NSImageLeft;
	_statusItem.menu					= self.statusItemMenu;
	_statusItem.button.title			= [NSBundle.mainBundle objectForInfoDictionaryKey:(__bridge NSString*)kCFBundleNameKey];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// update lal
	[self updateLaunchAtLoginMenuItem];
	
	// subscribe to thermal state changes
	[self updateStatusItemImage:nil];// To receive NSProcessInfoThermalStateDidChangeNotification, you must access the thermalState prior to registering for the notification.
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateStatusItemImage:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
	
	// start sensor singleton
	iohid = IOHID.shared;
	
	// update StatusItem immediately
	[self updateCPU:nil];
	[self updateSSD:nil];
	[self updateBatt:nil];
	
	// start cpu timer
	timer_cpu			= [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(updateCPU:) userInfo:nil repeats:YES];
	timer_cpu.tolerance	= 1.0;
	// start ssd timer
	timer_ssd			= [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(updateSSD:) userInfo:nil repeats:YES];
	timer_cpu.tolerance	= 1.0;
	// start batt timer
	timer_batt			= [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(updateSSD:) userInfo:nil repeats:YES];
	timer_batt.tolerance= 1.0;
	
	// populate all temps menu
	self.allTempsMenu.font	= [NSFont monospacedSystemFontOfSize:-1.0 weight:NSFontWeightRegular];
	
	for (TinySensor *sensor in [iohid allSensors]) {
		NSMenuItem *item 		= [self.allTempsMenu addItemWithTitle:sensor.nameAndTemperature action:@selector(allTempAction:) keyEquivalent:@""];
		item.representedObject	= sensor;
	}
}

- (NSString *)formattedTempForTemp:(double)temp {
	if (temp < 0.0) {
		return @"-";
	} else {
		return [NSString stringWithFormat:@"%.0fºC", round(temp)];
	}
}

//MARK: StatusItem Updates
- (void)updateStatusItemToolTip {
	NSString *cpu	= [self formattedTempForTemp:temp_cpu];
	NSString *ssd	= [self formattedTempForTemp:temp_ssd];
	NSString *batt	= [self formattedTempForTemp:temp_batt];
	self.statusItem.button.toolTip	= [NSString stringWithFormat:@"CPU:%@ SSD:%@ Batt:%@ Thermal State: %@", cpu, ssd, batt, thermalState];
}
- (void)updateCPU:(NSTimer *)timer {
	temp_cpu	= [iohid readCPUTemperature];
	self.statusItem.button.title	= [self formattedTempForTemp:temp_cpu];
	[self updateStatusItemToolTip];
}
- (void)updateSSD:(NSTimer *)timer {
	temp_ssd = [iohid readSSDTemperature];
	[self updateStatusItemToolTip];
}
- (void)updateBatt:(NSTimer *)timer {
	temp_batt = [iohid readBatteryTemperature];
	[self updateStatusItemToolTip];
}

- (void)updateStatusItemImage:(NSNotification *)n {
	NSProcessInfoThermalState state = NSProcessInfo.processInfo.thermalState;

	switch (state) {
		case NSProcessInfoThermalStateNominal:
			self.statusItem.button.image	= nil;
			thermalState	= @"Normal";
			break;
		case NSProcessInfoThermalStateFair:
			self.statusItem.button.image	= [NSImage imageWithSystemSymbolName:@"thermometer.low" variableValue:0.33 accessibilityDescription:@"Thermal State: Fair"];
			thermalState	= @"Fair";
			break;
		case NSProcessInfoThermalStateSerious: {
			NSImage *img	= [NSImage imageWithSystemSymbolName:@"thermometer.medium" variableValue:0.66 accessibilityDescription:@"Thermal State: Serious"];
			self.statusItem.button.image = [self image:img tintedWithColor:NSColor.systemOrangeColor];
			thermalState	= @"Serious";
		}
			break;
		case NSProcessInfoThermalStateCritical: {
			NSImage *img	= [NSImage imageWithSystemSymbolName:@"thermometer.high" variableValue:1.0 accessibilityDescription:@"Thermal State: Critical"];
			self.statusItem.button.image = [self image:img tintedWithColor:NSColor.systemRedColor];
			thermalState	= @"Critical";
		}
			break;
	}
}

- (NSImage *)image:(NSImage *)img tintedWithColor:(NSColor *)tint {
	NSImage *image = [img copy];
	if (tint) {
		[image setTemplate:NO];
		[image lockFocus];
		[tint set];
		NSRect imageRect = {NSZeroPoint, [image size]};
		NSRectFillUsingOperation(imageRect, NSCompositingOperationSourceIn);
		[image unlockFocus];
	}
	return image;
}

//MARK: all temps menu
- (void)menuWillOpen:(NSMenu *)menu {
	if (menu == self.allTempsMenu) {
		NSLog(@"Start");
		// timer has to run in NSEventTrackingRunLoopMode for real-time NSMenu updates
		timer_all = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(updateAllTemps:) userInfo:nil repeats:YES];
		[[NSRunLoop currentRunLoop] addTimer:timer_all forMode:NSEventTrackingRunLoopMode];
	}
}
- (void)menuDidClose:(NSMenu *)menu {
	if (menu == self.allTempsMenu) {
		[timer_all invalidate];
	}
}
- (void)updateAllTemps:(NSTimer *)timer {
	for (NSMenuItem *item in self.allTempsMenu.itemArray) {
		item.title	= [item.representedObject nameAndTemperature];
	}
}
- (void)allTempAction:(NSMenuItem *)item {
	// empty action to enable all Temp menu items
}

//MARK: Launch at Login
- (void)updateLaunchAtLoginMenuItem {
	if (@available(macOS 13.0, *)) {
		SMAppServiceStatus status	= SMAppService.mainAppService.status;
		self.lal.state				=  (status == SMAppServiceStatusEnabled);
		self.lal.enabled			= YES;
	}
}
- (IBAction)toggleLaunchAtLogin:(NSMenuItem *)sender {
	if (@available(macOS 13.0, *)) {
		SMAppService *as	= SMAppService.mainAppService;
		NSError *error;
		if (as.status == SMAppServiceStatusEnabled) {
			[as unregisterAndReturnError:&error];
			if (error) {
				NSLog(@"Unregistered with error: %@",error);
			}
		} else {
			[as registerAndReturnError:&error];
			if (error) {
				NSLog(@"Registered with error: %@",error);
			}
		}
		sender.state	= !sender.state;
	}
}


//MARK: AppDelegate
- (void)applicationWillTerminate:(NSNotification *)aNotification {
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return NO;
}
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return NO;
}
@end
