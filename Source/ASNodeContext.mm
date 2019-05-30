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

void ASNodeContextPush(unowned ASNodeContext *context) {
  gContexts.push(context);
}

ASNodeContext *ASNodeContextGet() {
  return gContexts.empty() ? nil : gContexts.top();
}

void ASNodeContextPop() {
  ASDisplayNodeCAssertFalse(gContexts.empty());
  gContexts.pop();
}

#else   // !AS_TLS_AVAILABLE

// Only on 32-bit simulator. Performance expendable.

// Points to a NSMutableArray<ASNodeContext *>.
static constexpr NSString *ASNodeContextStackKey = @"org.TextureGroup.Texture.nodeContexts";

void ASNodeContextPush(ASNodeContext *context) {
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
  [NSThread.currentThread.threadDictionary[ASNodeContextStackKey] removeLastObject];
}

#endif  // !AS_TLS_AVAILABLE

@implementation ASNodeContext

@end
