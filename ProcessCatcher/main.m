//
//  main.m
//  ProcessCatcher
//
//  Created by Thomas the Tank Engine on 13/11/2018.
//  Copyright © 2018 Squid. All rights reserved.
//

//ProcessCatcher injects a dylib into a running process. It needs to be run as root.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "mach_inject.h"
@import MachO;

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
    printf("bootstrap: %s\n", [bootstrapPath UTF8String]);
    void *mod = dlopen([bootstrapPath UTF8String], RTLD_NOW | RTLD_LOCAL);
    if(!mod) {
        printf("Failed (mod)\n");
        exit(1);
    }
    
    void *bootstrap = dlsym(mod, "bootstrap");
    if(!bootstrap) {
        printf("Failed (bootstrap)\n");
        exit(1);
    }
    
    const char *dylib = [path UTF8String];
    printf("Injecting...\n");
    mach_inject((mach_inject_entry)bootstrap, dylib, strlen(dylib) + 1, pid, 0);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if(argc < 4) exit(1);
        NSMutableArray *args = [NSMutableArray array];
        for(int i = 0; i < argc; i++) {
            [args addObject:@(argv[i])];
        }
        
        //args[0] will be the path to ProcessCatcher (obviously)
        //args[1] *should* be the pid of the process
        //args[2] *should* be the path to MaxOS (but any dylib could be used in theory)
        //args[3] *should* be the path to bootstrap.dylib (required because this program runs as root)
        
        pid_t pid = [args[1] intValue];
        NSString *dylib = args[2];
        NSString *bootstrap = args[3];
        
        if(!isPidValid(pid)) {
            printf("Failed (pid)\n");
            exit(1);
        }
        
        inject(pid, dylib, bootstrap);
    }
    return 0;
}
