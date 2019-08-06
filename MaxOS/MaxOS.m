//
//  MaxOS.m
//  Checkers
//
//  Created by Theresa May on 09/11/2018.
//  Copyright Â© 2018 Squid. All rights reserved.
//

//This is the library which will be injected into processes.

#import "MaxOS.h"
#import <dlfcn.h>
@import AppKit;
@import ObjectiveC;
@import Foundation;
@import MachO;

static NSMutableArray *toLog;

#define TWEAKSDIRECTORY @"/Library/Application\\ Support/MaxOS/Tweaks/"
#define LOGDIR @"/Library/Application\\ Support/MaxOS/"

void fileLog() {
    NSString *path = [LOGDIR stringByAppendingPathComponent:@"MaxOSLog.txt"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSMutableString *str = [NSMutableString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    for(NSString *string in toLog) {
        [str appendFormat:@"%@\n", string];
    }
    NSError *err;
    [str writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if(!err) {
        [toLog removeAllObjects]; //Only remove the objects if the write was successful. If it wasn't, we can try again next time.
    }
}

void addToLog(NSString *toAdd) {
    [toLog addObject:toAdd];
}



#define SQLog(format_string,...) \
((addToLog([NSString stringWithFormat:format_string,##__VA_ARGS__])))

//For calling orig from hooked methods. Tweaks don't actually have a way to use this yet, but it is very useful. NSInvocation is required if you are writing a tweak (unless you decide to use this).
//Since this returns void *, you need to cast the return value. int would be *(int *), NSString would be (__bridge NSString *), etc.
//My (rather brief) testing showed that it works ok, but it probably has some blindingly obvious shortcomings that I hadn't noticed.
void *callOrig(SEL callName, id target, ...) {
    Class cls = object_isClass(target) ? target : object_getClass(target);
    
    SEL orig_sel = NSSelectorFromString([@"orig_" stringByAppendingString:NSStringFromSelector(callName)]);
    BOOL classMethod = NO;
    Method method = class_getInstanceMethod(cls, callName);
    if(method_getImplementation(method) == NULL) {
        method = class_getClassMethod(cls, orig_sel);
        classMethod = YES;
    }
    
    if(method == NULL) return NULL;
    
    int arg_count = method_getNumberOfArguments(method) - 2;
    
    NSMutableArray *arguments = [NSMutableArray array];
    
    va_list args;
    va_start(args, target);
    for(int i = 0; i < arg_count; i++) {
        void *arg = va_arg(args, void *);
        [arguments addObject:[NSValue valueWithPointer:arg]];
    }
    va_end(args);
    
    NSMethodSignature *sig = [classMethod ? cls : target methodSignatureForSelector:orig_sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
    [invocation setSelector:orig_sel];
    
    for(int i = 0; i < [arguments count]; i++) {
        id obj = arguments[i];
        
        void *ptr = [obj pointerValue];
        [invocation setArgument:&ptr atIndex:i + 2];
    }
    
    [invocation setTarget:target];
    [invocation invoke];
    
    NSUInteger len = [sig methodReturnLength];
    
    void *buffer = (void *)malloc(len);
    
    const char *retEnc = [sig methodReturnType];
    if(strcmp("v", retEnc) == 0) {
        return 0x0; //0x0 because it looks like a face.
    }
    
    BOOL isObject = [@(retEnc) containsString:@"@"];
    [invocation getReturnValue:isObject ? &buffer : buffer];
    
    return buffer;
}

#define origc(...) callOrig(_cmd, self, ##__VA_ARGS__)

//This makes it easier to write tweaks by removing the need to preface any methods you wish to hook with 'hook_'.
NSDictionary *mutualSelectors(Class one, Class two) {
    NSMutableArray *class = [NSMutableArray array];
    unsigned int classMethodCount;
    
    Method *classMethods = class_copyMethodList(object_getClass(one), &classMethodCount);
    NSLog(@"%u", classMethodCount);
    for(int i = 0; i < classMethodCount; i++) {
        SEL selector = method_getName(classMethods[i]);
        if(class_respondsToSelector(two, selector)) {
            [class addObject:NSStringFromSelector(selector)];
        }
    }
    
    NSMutableArray *instance = [NSMutableArray array];
    unsigned int instanceMethodCount;
    Method *instanceMethods = class_copyMethodList(one, &instanceMethodCount);
    NSLog(@"%u", instanceMethodCount);
    for(int i = 0; i < instanceMethodCount; i++) {
        SEL selector = method_getName(instanceMethods[i]);
        if(class_respondsToSelector(two, selector)) {
            [instance addObject:NSStringFromSelector(selector)];
        }
    }
    
    return @{
             @"Class" : class,
             @"Instance" : instance
             };
}

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

NSArray *classesFromDylib(NSString *dylibPath) {
    //We need the symbols from the dylib. I'm not clever enough to create something like class-dump, so let's just parse the output from the nm command.
    NSString *nm = output(@"/usr/bin/nm", @[@"-just-symbol-name", dylibPath]);
    
    NSArray *lines = [[nm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    NSMutableArray *classNames = [NSMutableArray array];
    
    NSString *classPrefix = @"_OBJC_CLASS_$_";
    for(NSString *line in lines) {
        if([line hasPrefix:classPrefix]) {
            //This isn't great, because we end up with a bunch of classes like NSArray. Still, it is way faster than looking through every loaded class.
            [classNames addObject:[[line stringByReplacingOccurrencesOfString:classPrefix withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
    }
    
    return classNames;
}

static NSMutableArray *dylibClasses;

@implementation MaxOS

+(NSArray *)tweaksToInject {
    NSString *dir = TWEAKSDIRECTORY;
    
    NSError *err;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&err];
    if(err) return @[];
    
    NSArray *filters = [files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@", @"plist"]];
    
    NSMutableArray *inject = [NSMutableArray array];
    for(NSString *plist in filters) {
        NSString *plistPath = [dir stringByAppendingPathComponent:plist];
        NSDictionary *filter = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        
        NSArray *bundles = filter[@"Filter"][@"Bundles"];
        for(NSString *bID in bundles) {
            NSBundle *bundle = [NSBundle bundleWithIdentifier:bID];
            if([bundle isLoaded]) {
                [inject addObject:[[plistPath stringByDeletingPathExtension] stringByAppendingString:@".dylib"]];
            }
        }
    }
    [inject sortUsingSelector:@selector(caseInsensitiveCompare:)];
    return inject;
}

+(void)loadDylib:(NSString *)dylib {
    SQLog(@"Loading %@ into %@.", dylib, [[NSBundle mainBundle] bundleIdentifier]);
    if(!dlopen([dylib UTF8String], RTLD_LAZY | RTLD_GLOBAL)) {
        SQLog(@"Unable to load %@!", dylib);
        return;
    }
    
    [dylibClasses addObjectsFromArray:classesFromDylib(dylib)];
}

@end

@interface Mob : NSObject
@end

@implementation Mob

+(void)startTheHunt {
    for(NSString *class in dylibClasses) {
        Class hookClass = NSClassFromString(class);
        if (![[class lowercaseString] hasSuffix:@"_hook"]) {
            continue;
        }
        [self gotOne:hookClass];
    }
}

+(void)gotOne:(Class)victim {
    const char *className = class_getName(victim);
    SQLog(@"Performing hooks for %@", NSStringFromClass(victim));
    
    Class metaClass = victim;
    if (!class_isMetaClass(metaClass) && className) {
        Class maybeMeta = objc_getMetaClass(className);
        if (maybeMeta) {
            metaClass = maybeMeta;
        }
        
        NSArray *targetClasses = @[[[@(className) stringByReplacingOccurrencesOfString:@"_hook" withString:@""] stringByReplacingOccurrencesOfString:@"_Hook" withString:@""]];
        
        for (NSString *targetClassName in targetClasses) {
            Class targetClass = NSClassFromString(targetClassName);
            if (!targetClass) {
                continue;
            }
            SQLog(@"%@ hooks %@", NSStringFromClass(victim), NSStringFromClass(targetClass));
            [self hookClassAndHisFriend:victim
                            targetClass:targetClass];
        }
    }
}

+(void)hookClassAndHisFriend:(Class)hookClass
                 targetClass:(Class)friend {
    
    NSDictionary *mutual = mutualSelectors(hookClass, friend);
    SQLog(@"Mutual selectors for classes %@ and %@: %@", NSStringFromClass(hookClass), NSStringFromClass(friend), mutual);
    
    NSArray *class = mutual[@"Class"];
    if([class count] > 0) {
        Class metaClass = objc_getMetaClass(class_getName(friend));
#define targetClass metaClass
        for(NSString *classMethodName in class) {
            SEL selector = NSSelectorFromString(classMethodName);
            
            Method originalMethod = class_getClassMethod(targetClass, selector);
            Method hookMethod = class_getClassMethod(hookClass, selector);
            
            const char *origType = method_getTypeEncoding(originalMethod);
            const char *hookType = method_getTypeEncoding(hookMethod);
            
            if(strcmp(origType, hookType) != 0) {
                SQLog(@"Type encoding mismatch! Class: %@, Hooked from: %@", NSStringFromClass(targetClass), NSStringFromClass(hookClass));
                return;
            }
            
            //%orig
            IMP orig = method_getImplementation(originalMethod);
            SEL orig_sel = NSSelectorFromString([@"orig_" stringByAppendingString:NSStringFromSelector(selector)]); //orig_selectorName
            class_addMethod(targetClass, orig_sel, orig, origType);
            if([targetClass respondsToSelector:orig_sel]) {
                SQLog(@"%@ successfully added to class %@", NSStringFromSelector(orig_sel), NSStringFromClass(targetClass));
            } else {
                SQLog(@"Failed to add %@ to class %@", NSStringFromSelector(orig_sel), NSStringFromClass(targetClass));
            }
            
            class_addMethod(targetClass, selector, method_getImplementation(originalMethod), origType);
            
            IMP previousImplementation = class_replaceMethod(targetClass, selector, method_getImplementation(hookMethod), origType);
            if (previousImplementation != NULL) {
                SQLog(@"Hooked +[%s %@]", class_getName(targetClass), NSStringFromSelector(selector));
            } else {
                SQLog(@"Hook failed +[%s %@]", class_getName(targetClass), NSStringFromSelector(selector));
            }
        }
    }
    
#undef targetClass
    
    NSArray *instance = mutual[@"Instance"];
    if([instance count] > 0) {
        for(NSString *instanceMethodName in instance) {
            SEL selector = NSSelectorFromString(instanceMethodName);
            
            Method originalMethod = class_getInstanceMethod(friend, selector);
            Method hookMethod = class_getInstanceMethod(hookClass, selector);
            
            const char *origType = method_getTypeEncoding(originalMethod);
            const char *hookType = method_getTypeEncoding(hookMethod);
            
            if(strcmp(origType, hookType) != 0) {
                SQLog(@"Type encoding mismatch! Class: %@, Hooked from: %@", NSStringFromClass(friend), NSStringFromClass(hookClass));
                return;
            }
            
            //%orig
            IMP orig = method_getImplementation(originalMethod);
            SEL orig_sel = NSSelectorFromString([@"orig_" stringByAppendingString:NSStringFromSelector(selector)]); //orig_selectorName
            class_addMethod(friend, orig_sel, orig, origType);
            
            if([friend instancesRespondToSelector:orig_sel]) {
                SQLog(@"%@ successfully added to class %@", NSStringFromSelector(orig_sel), NSStringFromClass(friend));
            } else {
                SQLog(@"Failed to add %@ to class %@", NSStringFromSelector(orig_sel), NSStringFromClass(friend));
            }
            
            class_addMethod(friend, selector, method_getImplementation(hookMethod), origType);
            
            IMP previousImplementation = class_replaceMethod(friend, selector, method_getImplementation(hookMethod), origType);
            if (previousImplementation != NULL) {
                SQLog(@"Hooked -[%s %@]", class_getName(friend), NSStringFromSelector(selector));
            } else {
                SQLog(@"Hook failed -[%s %@]", class_getName(friend), NSStringFromSelector(selector));
            }
        }
    }
}

@end

__attribute__((constructor)) void modify() {
    toLog = [NSMutableArray array];
    dylibClasses = [NSMutableArray array];
    
    unlink([[LOGDIR stringByAppendingPathComponent:@"MaxOSLog.txt"] UTF8String]); //aaaaakillit
    SQLog(@"MaxOS loaded into process %@.", [[NSBundle mainBundle] bundleIdentifier]);
    
    NSArray *dylibs = [MaxOS tweaksToInject];
    for(NSString *dylib in dylibs) {
        [MaxOS loadDylib:dylib];
    }
    
    [Mob startTheHunt];
    SQLog(@"Classes loaded by dylibs: %@", dylibClasses);
    fileLog();
}

//And they all lived happily ever after.
