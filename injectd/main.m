//
//  main.m
//  injectd
//
//  Created by my imagination on 13/11/2018.
//  Copyright © 2018 Squid. All rights reserved.
//

@import Foundation;
@import AppKit;
@import MachO;
#import <dlfcn.h>
#import "mach_inject.h"

#define BOOTSTRAP @"/Library/Application Support/MaxOS/bootstrap.dylib"
#define MAXOS @"/Library/Application Support/MaxOS/libMaxOS.dylib"

NSString *output(NSString *command, NSArray *args) {
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:command];
	[task setArguments:args];
	
	NSPipe *outPipe = [NSPipe pipe];
	[task setStandardOutput:outPipe];
	
	[task launch];
	[task waitUntilExit];
	return [[NSString alloc] initWithData:[[outPipe fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
}

BOOL isPidValid(pid_t pid) {
	//ps -p <PID> -o command=
	NSString *cmdOutput = output(@"/bin/ps", @[@"-p", [@(pid) stringValue], @"-o", @"command="]);
	if([cmdOutput length] < 1) {
		return NO;
	}
	return YES;
}

void inject(pid_t pid, NSString *path, NSString *bootstrapPath) {
	printf("\033[1;34mstarting injection procedure\033[0m\n");
	void *bootstrapLoad = dlopen([bootstrapPath UTF8String], RTLD_NOW | RTLD_LOCAL);
	if(!bootstrapLoad) {
		printf("\033[1;31merror: \033[0mcould not load bootstrap.dylib (\033[01;33mdlopen()\033[0m)\n");
		return;
	}
	
	void *bootstrap = dlsym(bootstrapLoad, "bootstrap");
	if(!bootstrap) {
		printf("\033[1;31merror: \033[0mbootstrap symbol not found (\033[01;33mdlsym()\033[0m)\n");
		return;
	}
	
	const char *dylib = [path UTF8String];
	const mach_error_t err = mach_inject((mach_inject_entry)bootstrap, dylib, strlen(dylib) + 1, pid, 0);
	printf("\033[1;32mfinished injection procedure with code %d\033[0m\n", err);
}

void catchProcess(const pid_t pid) {
	if(!isPidValid(pid)) {
		printf("\033[1;31merror: \033[0mpid \033[0;32m%d\033[0m is invalid\n", pid);
		return;
	}
	
	//This is temporary; the crossover needs to be better in the future.
	inject(pid, MAXOS, BOOTSTRAP);
}

@interface InjectDaemon : NSObject
@end

@implementation InjectDaemon

-(void)respondToNotification:(NSNotification *)notif {
	//Get the pid for the process to inject into.
	NSDictionary *userInfo = [notif userInfo];
	NSRunningApplication *app = userInfo[NSWorkspaceApplicationKey];
	pid_t pid = [app processIdentifier];
	
	printf("\033[01;33minjectd: \033[0m");
	printf("detected process load with pid %d \033[0;32m(%s)\033[0m\n", pid, [[app bundleIdentifier] UTF8String]);

	catchProcess(pid);
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        InjectDaemon *daemon = [InjectDaemon new];
		
		//Start observing for process launches.
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:daemon selector:@selector(respondToNotification:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
