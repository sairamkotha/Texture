//
//  ASNodeContext+Private.h
//  AsyncDisplayKit
//
//  Created by Adlai Holler on 5/29/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <AsyncDisplayKit/ASNodeContext.h>
#import <AsyncDisplayKit/ASThread.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Only here during experimentation.
 */
NS_INLINE void ASNodeContextPushNewIfEnabled() {
  if (ASActivateExperimentalFeature(ASExperimentalNodeContext)) {
    ASNodeContextPush([[ASNodeContext alloc] init]);
  }
}

NS_INLINE void ASNodeContextPopIfEnabled() {
  if (ASActivateExperimentalFeature(ASExperimentalNodeContext)) {
    ASNodeContextPop();
  }
}

@interface ASNodeContext () {
@package
  AS::RecursiveMutex _mutex;
}

@end

NS_ASSUME_NONNULL_END
