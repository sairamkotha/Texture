//
//  _ASDisplayViewAccessiblity.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#ifndef ASDK_ACCESSIBILITY_DISABLE

#import <AsyncDisplayKit/_ASDisplayView.h>
#import <AsyncDisplayKit/ASAvailability.h>
#import <AsyncDisplayKit/ASCollectionNode.h>
#import <AsyncDisplayKit/ASDisplayNodeExtras.h>
#import <AsyncDisplayKit/ASDisplayNode+FrameworkPrivate.h>
#import <AsyncDisplayKit/ASDisplayNode+Ancestry.h>
#import <AsyncDisplayKit/ASDisplayNodeInternal.h>
#import <AsyncDisplayKit/ASTableNode.h>

#import <queue>

NS_INLINE UIAccessibilityTraits InteractiveAccessibilityTraitsMask() {
  return UIAccessibilityTraitLink | UIAccessibilityTraitKeyboardKey | UIAccessibilityTraitButton;
}

NS_INLINE BOOL ASIsLeafNode(__unsafe_unretained ASDisplayNode *node) {
  return node.subnodes.count == 0;
}

#pragma mark - UIAccessibilityElement

@protocol ASAccessibilityElementPositioning

@property (nonatomic, readonly) CGRect accessibilityFrame;

@end

typedef NSComparisonResult (^SortAccessibilityElementsComparator)(id<ASAccessibilityElementPositioning>, id<ASAccessibilityElementPositioning>);

/// Sort accessiblity elements first by y and than by x origin.
static void SortAccessibilityElements(NSMutableArray *elements)
{
  ASDisplayNodeCAssertNotNil(elements, @"Should pass in a NSMutableArray");
  
  static SortAccessibilityElementsComparator comparator = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
      comparator = ^NSComparisonResult(id<ASAccessibilityElementPositioning> a, id<ASAccessibilityElementPositioning> b) {
        CGPoint originA = a.accessibilityFrame.origin;
        CGPoint originB = b.accessibilityFrame.origin;
        if (originA.y == originB.y) {
          if (originA.x == originB.x) {
            return NSOrderedSame;
          }
          return (originA.x < originB.x) ? NSOrderedAscending : NSOrderedDescending;
        }
        return (originA.y < originB.y) ? NSOrderedAscending : NSOrderedDescending;
      };
  });
  [elements sortUsingComparator:comparator];
}

@interface ASAccessibilityElement : UIAccessibilityElement<ASAccessibilityElementPositioning>

@property (nonatomic) ASDisplayNode *node;
@property (nonatomic) ASDisplayNode *containerNode;

+ (ASAccessibilityElement *)accessibilityElementWithContainerView:(UIView *)containerView node:(ASDisplayNode *)node;

@end

@implementation ASAccessibilityElement

+ (ASAccessibilityElement *)accessibilityElementWithContainerView:(UIView *)containerView node:(ASDisplayNode *)node
{
  ASAccessibilityElement *accessibilityElement = [[ASAccessibilityElement alloc] initWithAccessibilityContainer:containerView];
  accessibilityElement.node = node;
  accessibilityElement.accessibilityIdentifier = node.accessibilityIdentifier;
  accessibilityElement.accessibilityLabel = node.accessibilityLabel;
  accessibilityElement.accessibilityHint = node.accessibilityHint;
  accessibilityElement.accessibilityValue = node.accessibilityValue;
  accessibilityElement.accessibilityTraits = node.accessibilityTraits;
  if (AS_AVAILABLE_IOS_TVOS(11, 11)) {
    accessibilityElement.accessibilityAttributedLabel = node.accessibilityAttributedLabel;
    accessibilityElement.accessibilityAttributedHint = node.accessibilityAttributedHint;
    accessibilityElement.accessibilityAttributedValue = node.accessibilityAttributedValue;
  }
  return accessibilityElement;
}

- (CGRect)accessibilityFrame
{
  ASDisplayNode *supernode = [self.node firstNonLayerNode];
  ASDisplayNodeAssert(!supernode.isLayerBacked, @"No non-layerbacked node found.");

  return [self.node.layer convertRect:self.node.bounds toLayer:ASFindWindowOfLayer(self.node.layer).layer];
}

@end

#pragma mark - _ASDisplayView / UIAccessibilityContainer

@interface ASAccessibilityCustomAction : UIAccessibilityCustomAction<ASAccessibilityElementPositioning>

@property (nonatomic) ASDisplayNode *node;

@end

@implementation ASAccessibilityCustomAction

- (CGRect)accessibilityFrame
{
  ASDisplayNode *supernode = [self.node firstNonLayerNode];
  ASDisplayNodeAssert(!supernode.isLayerBacked, @"No non-layerbacked node found.");

  return [self.node.layer convertRect:self.node.bounds toLayer:ASFindWindowOfLayer(self.node.layer).layer];
}

@end

/// Collect all subnodes for the given node by walking down the subnode tree and calculates the screen coordinates based on the containerNode and container. This is necessary for layer backed nodes or rasterrized subtrees as no UIView instance for this node exists.
static void CollectAccessibilityElementsForLayerBackedOrRasterizedNode(ASDisplayNode *node, ASDisplayNode *containerNode, id container, NSMutableArray *elements)
{
  ASDisplayNodeCAssertNotNil(elements, @"Should pass in a NSMutableArray");

  // Iterate any node in the tree and either collect nodes that are accessibility elements
  // or leaf nodes that are accessibility containers
  ASDisplayNodePerformBlockOnEveryNodeBFS(node, ^(ASDisplayNode * _Nonnull currentNode) {
    if (currentNode != containerNode) {
      if (currentNode.isAccessibilityElement) {
        // For every subnode that is layer backed or it's supernode has subtree rasterization enabled
        // we have to create a UIAccessibilityElement as no view for this node exists
        UIAccessibilityElement *accessibilityElement = [ASAccessibilityElement accessibilityElementWithContainerView:container node:currentNode];
        [elements addObject:accessibilityElement];
      } else if (ASIsLeafNode(currentNode)) {
        // In leaf nodes that are layer backed and acting as accessibility container we call
        // through to the accessibilityElements method.
        if (ASActivateExperimentalFeature(ASExperimentalTextNode2A11YContainer)) {
          [elements addObjectsFromArray:currentNode.accessibilityElements];
        }
      }
    }
  });
}

/// Called from the usual accessibility elements collection function for a container to collect all subnodes accessibilityLabels
static void AggregateSublabelsOrCustomActionsForContainerNode(ASDisplayNode *containerNode, UIView *containerView, NSMutableArray *elements) {
  UIAccessibilityElement *accessiblityElement = [ASAccessibilityElement accessibilityElementWithContainerView:containerView node:containerNode];

  NSMutableArray<ASAccessibilityElement *> *labeledNodes = [[NSMutableArray alloc] init];
  NSMutableArray<ASAccessibilityCustomAction *> *actions = [[NSMutableArray alloc] init];
  std::queue<ASDisplayNode *> queue;
  queue.push(containerNode);

  // If the container does not have an accessibility label set, or if the label is meant for custom
  // actions only, then aggregate its subnodes' labels. Otherwise, treat the label as an overriden
  // value and do not perform the aggregation.
  BOOL shouldAggregateSubnodeLabels =
      (containerNode.accessibilityLabel.length == 0) ||
      (containerNode.accessibilityTraits & InteractiveAccessibilityTraitsMask());

  // Iterate through the whole subnode tree and aggregate
  ASDisplayNode *node = nil;
  while (!queue.empty()) {
    node = queue.front();
    queue.pop();

    if (node != containerNode && node.isAccessibilityContainer) {
      AggregateSublabelsOrCustomActionsForContainerNode(node, node.view, elements);
      continue;
    }


    // Aggregate either custom actions for specific accessibility traits or the accessibility labels
    // of the node
    if (node.accessibilityLabel.length > 0) {
      if (node.accessibilityTraits & InteractiveAccessibilityTraitsMask()) {
        ASAccessibilityCustomAction *action = [[ASAccessibilityCustomAction alloc] initWithName:node.accessibilityLabel target:node selector:@selector(performAccessibilityCustomAction:)];
        action.node = node;
        node.acessibilityCustomAction = action;
        [actions addObject:action];
      } else if (node == containerNode || shouldAggregateSubnodeLabels) {
        // Even though not surfaced to UIKit, create a non-interactive element for purposes of building sorted aggregated label.
        ASAccessibilityElement *nonInteractiveElement = [ASAccessibilityElement accessibilityElementWithContainerView:containerView node:node];
        [labeledNodes addObject:nonInteractiveElement];
      }
    }

    for (ASDisplayNode *subnode in node.subnodes) {
      queue.push(subnode);
    }
  }

  SortAccessibilityElements(labeledNodes);

  if (AS_AVAILABLE_IOS_TVOS(11, 11)) {
    NSArray *attributedLabels = [labeledNodes valueForKey:@"accessibilityAttributedLabel"];
    NSMutableAttributedString *attributedLabel = [NSMutableAttributedString new];
    [attributedLabels enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
      if (idx != 0) {
        [attributedLabel appendAttributedString:[[NSAttributedString alloc] initWithString:@", "]];
      }
      [attributedLabel appendAttributedString:(NSAttributedString *)obj];
    }];
    accessiblityElement.accessibilityAttributedLabel = attributedLabel;
  } else {
    NSArray *labels = [labeledNodes valueForKey:@"accessibilityLabel"];
    accessiblityElement.accessibilityLabel = [labels componentsJoinedByString:@", "];
  }

  SortAccessibilityElements(actions);
  accessiblityElement.accessibilityCustomActions = actions;

  [elements addObject:accessiblityElement];
}

/// Collect all accessibliity elements for a given node
static void CollectAccessibilityElements(ASDisplayNode *node, NSMutableArray *elements)
{
  ASDisplayNodeCAssertNotNil(elements, @"Should pass in a NSMutableArray");

  BOOL anySubNodeIsCollection = (nil != ASDisplayNodeFindFirstNode(node,
      ^BOOL(ASDisplayNode *nodeToCheck) {
    return ASDynamicCast(nodeToCheck, ASCollectionNode) != nil ||
           ASDynamicCast(nodeToCheck, ASTableNode) != nil;
  }));

  // Handle an accessibility container (collects accessibility labels or custom actions)
  if (node.isAccessibilityContainer && !anySubNodeIsCollection) {
    AggregateSublabelsOrCustomActionsForContainerNode(node, node.view, elements);
    return;
  }

  // Handle a rasterize node
  if (node.rasterizesSubtree) {
    CollectAccessibilityElementsForLayerBackedOrRasterizedNode(node, node, node.view, elements);
    return;
  }

  // Collect all subnodes accessiblity elements
  for (ASDisplayNode *subnode in node.subnodes) {
    if (subnode.isAccessibilityElement) {
      // An accessiblityElement can either be a UIView or a UIAccessibilityElement
      if (subnode.isLayerBacked) {
        // No view for layer backed nodes exist. It's necessary to create a UIAccessibilityElement that represents this node
        UIAccessibilityElement *accessiblityElement = [ASAccessibilityElement accessibilityElementWithContainerView:node.view node:subnode];
        [elements addObject:accessiblityElement];
      } else {
        // Accessiblity element is not layer backed just add the view as accessibility element
        [elements addObject:subnode.view];
      }
    } else if (subnode.isLayerBacked) {
      // Go down the hierarchy for layer backed subnodes which are also accessibility container
      // and collect all of the UIAccessibilityElement
      CollectAccessibilityElementsForLayerBackedOrRasterizedNode(subnode, node, node.view, elements);
    } else if ([subnode accessibilityElementCount] > 0) {
      // _ASDisplayView is itself a UIAccessibilityContainer just add it, UIKit will call the accessiblity
      // methods of the nodes _ASDisplayView
      [elements addObject:subnode.view];
    }
  }
}

@interface _ASDisplayView () {
  NSArray *_accessibilityElements;
}

@end

@implementation _ASDisplayView (UIAccessibilityContainer)

#pragma mark - UIAccessibility

- (void)setAccessibilityElements:(NSArray *)accessibilityElements
{
  ASDisplayNodeAssertMainThread();
  _accessibilityElements = accessibilityElements;
}

- (NSArray *)accessibilityElements
{
  ASDisplayNodeAssertMainThread();

  ASDisplayNode *viewNode = self.asyncdisplaykit_node;
  if (viewNode == nil) {
    return @[];
  }

  if (_accessibilityElements == nil) {
    _accessibilityElements = [viewNode accessibilityElements];
  }
  return _accessibilityElements;
}

@end

@implementation ASDisplayNode (AccessibilityInternal)

- (void)setAccessibilityElements:(NSArray *)accessibilityElements
{
  // Bridge through calling to view to invalidate accessibility elements
  // If the view is layer backed it's likely a leaf node too what means this will be a no op
  // but the caching will happening on the next non layer node anyway.
  [_view setAccessibilityElements:accessibilityElements];
}

- (NSArray *)accessibilityElements
{
  if (!self.isNodeLoaded) {
    ASDisplayNodeFailAssert(@"Cannot access accessibilityElements since node is not loaded");
    return @[];
  }
  NSMutableArray *accessibilityElements = [[NSMutableArray alloc] init];
  CollectAccessibilityElements(self, accessibilityElements);
  SortAccessibilityElements(accessibilityElements);
  return accessibilityElements;
}

@end

@implementation _ASDisplayView (UIAccessibilityAction)

- (BOOL)accessibilityActivate {
  return [self.asyncdisplaykit_node accessibilityActivate];
}

- (void)accessibilityIncrement {
  [self.asyncdisplaykit_node accessibilityIncrement];
}

- (void)accessibilityDecrement {
  [self.asyncdisplaykit_node accessibilityDecrement];
}

- (BOOL)accessibilityScroll:(UIAccessibilityScrollDirection)direction {
  return [self.asyncdisplaykit_node accessibilityScroll:direction];
}

- (BOOL)accessibilityPerformEscape {
  return [self.asyncdisplaykit_node accessibilityPerformEscape];
}

- (BOOL)accessibilityPerformMagicTap {
  return [self.asyncdisplaykit_node accessibilityPerformMagicTap];
}

@end

#endif
