//
//  ASNodeContext.m
//  AsyncDisplayKit
//
//  Created by Adlai Holler on 5/29/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <AsyncDisplayKit/ASNodeContext+Private.h>

#import <AsyncDisplayKit/ASAssert.h>

#if AS_TLS_AVAILABLE

#import <stack>

static thread_local std::stack<ASNodeContext *> gContexts;

void _ASNodeContextPushNoCheck(unowned ASNodeContext *context) {
  gContexts.push(context);
}

ASNodeContext *ASNodeContextGet() {
  return gContexts.empty() ? nil : gContexts.top();
}

void ASNodeContextPop() {
  if (ASActivateExperimentalFeature(ASExperimentalNodeContext)) {
    ASDisplayNodeCAssertFalse(gContexts.empty());
    gContexts.pop();
  }
}

#else   // !AS_TLS_AVAILABLE

// Only on 32-bit simulator. Performance expendable.

// Points to a NSMutableArray<ASNodeContext *>.
static constexpr NSString *ASNodeContextStackKey = @"org.TextureGroup.Texture.nodeContexts";

void _ASNodeContextPushNoCheck(unowned ASNodeContext *context) {
  unowned NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
  unowned NSMutableArray<ASNodeContext *> *stack = td[ASNodeContextStackKey];
  if (!stack) {
    td[ASNodeContextStackKey] = [[NSMutableArray alloc] initWithObjects:context, nil];
  } else {
    [stack addObject:context];
  }
}

ASNodeContext *ASNodeContextGet() {
  return [NSThread.currentThread.threadDictionary[ASNodeContextStackKey] lastObject];
}

void ASNodeContextPop() {
  if (ASActivateExperimentalFeature(ASExperimentalNodeContext)) {
    [NSThread.currentThread.threadDictionary[ASNodeContextStackKey] removeLastObject];
  }
}

#endif  // !AS_TLS_AVAILABLE

void ASNodeContextPush(unowned ASNodeContext *context) {
  if (ASActivateExperimentalFeature(ASExperimentalNodeContext)) {
    _ASNodeContextPushNoCheck(context);
  }
}

void ASNodeContextPushNew() {
  if (ASActivateExperimentalFeature(ASExperimentalNodeContext)) {
    _ASNodeContextPushNoCheck([[ASNodeContext alloc] init]);
  }
}

@implementation ASNodeContext

@end
