#import "ProjectPanel.h"

@implementation ProjectPanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        NSTextField *label = [NSTextField labelWithString:@"Coming soon"];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textColor = [NSColor secondaryLabelColor];
        [self addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:NSZeroRect];
}

@end
