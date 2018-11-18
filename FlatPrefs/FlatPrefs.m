//
//  FlatPrefs.m
//  FlatPrefs
//
//  Created using ionic bonding on 11/11/2018. By Squ1dd13.
//  Copyright © 2018 Squid. All rights reserved.
//

#import "FlatPrefs.h"
@import AppKit;

@implementation FlatPrefs

@end

@interface NSFlippedView_Hook : NSView
@end

@implementation NSFlippedView_Hook

-(void)drawRect:(CGRect)rect {
    //NSFlippedView draws the stripes in this method.
    [super drawRect:rect];
}

@end
