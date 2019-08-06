//
//  main.m
//  injectd
//
//  Created by my imagination on 13/11/2018.
//  Copyright © 2018 Squid. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AppKit;

#define BOOTSTRAP @"/Library/Application\\ Support/MaxOS/bootstrap.dylib"
#define MAXOS @"/Library/Application\\ Support/MaxOS/libMaxOS.dylib"
#define PROC_CATCHER @"/Library/Application\\ Support/MaxOS/ProcessCatcher"

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
	
	//Run ProcessCatcher and give it the pid of the target process, the path to libMaxOS, and the path to the bootstrap dylib. The output is piped to /dev/null to avoid clutter.
	NSString *loadCommand = [NSString stringWithFormat:@"%@ %d %@ %@ > /dev/null 2>&1", PROC_CATCHER, pid, MAXOS, BOOTSTRAP];
	system([loadCommand UTF8String]);
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
