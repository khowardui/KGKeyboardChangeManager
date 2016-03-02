//
//  KGKeyboardChangeManager.m
//  KGKeyboardChangeManagerApp
//
//  Created by David Keegan on 1/16/13.
//  Copyright (c) 2013 David Keegan. All rights reserved.
//

#import "KGKeyboardChangeManager.h"

@interface KGKeyboardChangeManager()
@property (strong, atomic) NSMutableDictionary *changeCallbacks;
@property (strong, atomic) NSMutableDictionary *orientationCallbacks;
@property (nonatomic, readwrite, getter=keyboardWillShow) BOOL keyboardWillShow;
@property (nonatomic, readwrite, getter=isKeyboardShowing) BOOL keyboardShowing;
@property (nonatomic) BOOL orientationChange, didBecomeActive;
@end

@implementation KGKeyboardChangeManager

+ (KGKeyboardChangeManager *)sharedManager{
    static dispatch_once_t onceToken;
    static KGKeyboardChangeManager *sharedManager;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

+ (BOOL)isSystemVersionEqualToOrGreaterThan:(NSString *)version{
    return [[[UIDevice currentDevice] systemVersion] compare:version options:NSNumericSearch] != NSOrderedAscending;
}

- (instancetype)init{
    if(!(self = [super init])){
        return nil;
    }

    self.changeCallbacks = [NSMutableDictionary dictionary];
    self.orientationCallbacks = [NSMutableDictionary dictionary];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardWillShow:)
     name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardWillHide:)
     name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardDidShow:)
     name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardDidHide:)
     name:UIKeyboardDidHideNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardWillChangeFrame:)
     name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardDidChangeFrame:)
     name:UIKeyboardDidChangeFrameNotification object:nil];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(orientationDidChange:)
     name:UIDeviceOrientationDidChangeNotification object:nil];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(didBecomeActive:)
     name:UIApplicationDidBecomeActiveNotification object:nil];

    return self;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Observers

- (id)addObserverForKeyboardOrientationChangedWithBlock:(void(^)(CGRect keyboardRect))block{
    NSString *identifier = [[NSProcessInfo processInfo] globallyUniqueString];
    if(block){
        self.orientationCallbacks[identifier] = block;
    }
    return identifier;
}

- (id)addObserverForKeyboardChangedWithBlock:(KGKeyboardChangeManagerKeyboardChangedBlock)block{
    NSString *identifier = [[NSProcessInfo processInfo] globallyUniqueString];
    if(block){
        self.changeCallbacks[identifier] = block;
    }
    return identifier;
}

- (void)removeObserverWithIdentifier:(id)identifier{
    if(identifier){
        [self.orientationCallbacks removeObjectForKey:identifier];
        [self.changeCallbacks removeObjectForKey:identifier];
    }
}

- (void)didBecomeActive:(NSNotification *)notification{
    self.didBecomeActive = YES;
}

#pragma mark - Orientation

- (void)orientationDidChange:(NSNotification *)notification{
    if(self.isKeyboardShowing){
        self.orientationChange = YES;
    }

    // This code is here to undo orientationDidChange setting
    // orientationChange = YES when the app is returning to active.
    // If this is not done the code will think it is responding to an orientaion change
    if(self.didBecomeActive){
        self.orientationChange = NO;
        self.didBecomeActive = NO;
    }
}

#pragma mark - Keyboard

- (void)keyboardDidChange:(NSNotification *)notification show:(BOOL)show{
    CGRect keyboardEndFrame;
    NSTimeInterval animationDuration;
    UIViewAnimationCurve animationCurve;
    NSDictionary *userInfo = [notification userInfo];

    [userInfo[UIKeyboardAnimationCurveUserInfoKey] getValue:&animationCurve];
    [userInfo[UIKeyboardAnimationDurationUserInfoKey] getValue:&animationDuration];
    [userInfo[UIKeyboardFrameEndUserInfoKey] getValue:&keyboardEndFrame];

    CGRect newKeyboardEndFrame = keyboardEndFrame;

#ifndef KGKEYBOARD_APP_EXTENSIONS
    if(![KGKeyboardChangeManager isSystemVersionEqualToOrGreaterThan:(@"8.0")]){
        // The keyboard frame is in portrait space
        UIInterfaceOrientation interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
        if(interfaceOrientation == UIInterfaceOrientationPortrait){
            if(!show){
                newKeyboardEndFrame.origin.y = MIN(newKeyboardEndFrame.origin.y, CGRectGetHeight([[UIScreen mainScreen] bounds]));
            }
        }else if(interfaceOrientation == UIInterfaceOrientationLandscapeLeft){
            newKeyboardEndFrame.origin.y = CGRectGetMinX(keyboardEndFrame);
            newKeyboardEndFrame.size.width = CGRectGetHeight(keyboardEndFrame);
            newKeyboardEndFrame.size.height = CGRectGetWidth(keyboardEndFrame);
        }else if(interfaceOrientation == UIInterfaceOrientationLandscapeRight){
            newKeyboardEndFrame.size.width = CGRectGetHeight(keyboardEndFrame);
            newKeyboardEndFrame.size.height = CGRectGetWidth(keyboardEndFrame);
            newKeyboardEndFrame.origin.y = CGRectGetWidth([[UIScreen mainScreen] bounds])-CGRectGetMaxX(keyboardEndFrame);
        }else if(interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown){
            newKeyboardEndFrame = keyboardEndFrame;
            newKeyboardEndFrame.origin.y = CGRectGetHeight([[UIScreen mainScreen] bounds])-CGRectGetMaxY(keyboardEndFrame);
        }
    }
#endif

    // Call the appropriate callback
//    if(self.orientationChange){
//        [self.orientationCallbacks enumerateKeysAndObjectsUsingBlock:^(id key, KGKeyboardChangeManagerKeyboardOrientationBlock block, BOOL *stop){
//            if(block){
//                block(newKeyboardEndFrame);
//            }
//        }];
//    }else{
        [self.changeCallbacks enumerateKeysAndObjectsUsingBlock:^(id key, KGKeyboardChangeManagerKeyboardChangedBlock block, BOOL *stop){
            if(block){
                block(show, newKeyboardEndFrame, animationDuration, animationCurve);
            }
        }];
//    }
}

- (void)keyboardWillHide:(NSNotification *)notification{
    [self keyboardDidChange:notification show:NO];
}

- (void)keyboardDidHide:(NSNotification *)notification{
    self.keyboardShowing = NO;
}

- (void)keyboardWillShow:(NSNotification *)notification{
    self.keyboardWillShow = YES;
    [self keyboardDidChange:notification show:YES];
}

- (void)keyboardDidShow:(NSNotification *)notification{
    self.keyboardWillShow = NO;
    self.keyboardShowing = YES;
    self.orientationChange = NO;
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification{
    if(![KGKeyboardChangeManager isSystemVersionEqualToOrGreaterThan:@"8.0"]){
        return;
    }
    
    NSDictionary *userInfo = [notification userInfo];
    CGRect keyboardEndFrame;
    [userInfo[UIKeyboardFrameEndUserInfoKey] getValue:&keyboardEndFrame];

    if(CGRectGetMaxY(keyboardEndFrame) < CGRectGetMaxY([UIScreen mainScreen].bounds)){
        [self keyboardDidChange:notification show:NO];
    }
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification{
    if(![KGKeyboardChangeManager isSystemVersionEqualToOrGreaterThan:@"8.0"]){
        return;
    }
    
    NSDictionary *userInfo = [notification userInfo];
    CGRect keyboardEndFrame;
    [userInfo[UIKeyboardFrameEndUserInfoKey] getValue:&keyboardEndFrame];
    
    if(CGRectGetMaxY(keyboardEndFrame) < CGRectGetMaxY([UIScreen mainScreen].bounds)){
        self.keyboardShowing = NO;
    }
}

#pragma mark - Animation helper methods

+ (void)animateWithWithDuration:(NSTimeInterval)animationDuration animationCurve:(UIViewAnimationCurve)animationCurve andAnimation:(void(^)())animationBlock{
    [self animateWithWithDuration:animationDuration animationCurve:animationCurve animation:^{
        if(animationBlock){
            animationBlock();
        }
    } andCompletion:nil];
}

+ (void)animateWithWithDuration:(NSTimeInterval)animationDuration animationCurve:(UIViewAnimationCurve)animationCurve animation:(void(^)())animationBlock andCompletion:(void(^)(BOOL finished))completionBlock{
    [UIView animateWithDuration:animationDuration delay:0 options:(animationCurve << 16) animations:animationBlock completion:completionBlock];
}

@end
