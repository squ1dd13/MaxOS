//
//  main.m
//  injectd
//
//  Created by my imagination on 13/11/2018.
//  Copyright © 2018 Squid. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AppKit;

//injectd waits for apps to be launched and (indirectly) injects MaxOS into them. ('Indirectly' because it actually runs ProcessCatcher on the app, which is when the injection happens.)
//Launch this yourself, or use launchd instead.

//sudo chmod 4755 <this binary>
//sudo chown root <this binary>

static NSString *bootstrap;
static NSString *MaxOS;
static NSString *ProcessCatcher;

@interface Daemon : NSObject
@end

@implementation Daemon

-(void)respondToNotification:(NSNotification *)notif {
    NSDictionary *userInfo = [notif userInfo];
    NSRunningApplication *app = userInfo[NSWorkspaceApplicationKey];
    pid_t pid = [app processIdentifier];
    NSLog(@"Launched: %d", pid);
    
    NSString *command = [NSString stringWithFormat:@"sudo %@ %d %@ %@", ProcessCatcher, pid, MaxOS, bootstrap];
    
    setuid(0);
    system([command UTF8String]);
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if(getuid() < 1) {
            NSLog(@"Please don't run me as root. Instead, run 'sudo chmod 4755 <this program>' and 'sudo chown root <this program>' and run me normally.");
            exit(EXIT_FAILURE);
        }
        
        //Set these before we change to root.
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
        NSString *run = [docs stringByAppendingPathComponent:@"MaxOS"];
        
#define escape(str) [str stringByReplacingOccurrencesOfString:@" " withString:@"\\ "]
        
        bootstrap = escape([run stringByAppendingPathComponent:@"bootstrap.dylib"]);
        MaxOS = escape([run stringByAppendingPathComponent:@"libMaxOS.dylib"]);
        ProcessCatcher = escape([run stringByAppendingPathComponent:@"ProcessCatcher"]);
        Daemon *daemon = [Daemon new];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:daemon selector:@selector(respondToNotification:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
