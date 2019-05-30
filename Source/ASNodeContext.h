//
//  ASNodeContext.h
//  AsyncDisplayKit
//
//  Created by Adlai Holler on 5/29/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AsyncDisplayKit/AsyncDisplayKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ASNodeContext;

/**
 * Push the given context, which will apply to any nodes initialized with `init` instead of `initWithContext:`.
 *
 * A default context is provided by the system under the following circumstances:
 * - During the execution of a node block for ASCollectionNode or ASTableNode.
 * - During the call to `nodeForItem:` & related methods for ASCollectionNode or ASTableNode.
 * - During the execution of `calculateLayoutThatFits:` or `layoutSpecThatFits:` (context of receiver is pushed.)
 *
 * @discussion Generally users will not need to call this function themselves.
 */
AS_EXTERN void ASNodeContextPush(unowned ASNodeContext *context);

/**
 * Creates a new context and pushes it. This is useful during experimentation, so that if you aren't in the context
 * experiment, you won't create a context for no reason.
 */
AS_EXTERN void ASNodeContextPushNew(void);

/**
 * Get the current default context, if there is one.
 */
AS_EXTERN ASNodeContext *_Nullable ASNodeContextGet(void);

/**
 * Pop the current context, matching a previous call to ASNodeContextPush.
 */
AS_EXTERN void ASNodeContextPop(void);

/**
 * A node context is an object that is shared by, and uniquely identifies, an "embedding" of nodes. For example,
 * each cell in a collection view has its own context. Each ASViewController's node has its own context. You can
 * also explicitly establish a context for a node tree in another context.
 *
 * Node contexts store the mutex that is shared by all member nodes for synchronization. Operations such as addSubnode:
 * will lock the context's mutex for the duration of the work.
 *
 * Nodes may not be moved from one context to another. For instance, you may not detach a subnode of a cell node,
 * and reattach it to a subtree of another cell node in the same or another collection view.
 *
 * Node contexts are established in the `-initWithContext:` method and do not change. For ease of use, a default
 * context will be used from the `-init` method if available.
 */
AS_SUBCLASSING_RESTRICTED
@interface ASNodeContext : NSObject

@end

NS_ASSUME_NONNULL_END
