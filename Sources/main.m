#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>
#import <stdio.h>
#import <unistd.h>

// Menu-bar sticker that counts down to Demo Day.
// Orange is YC's #F26522. The date starts as a placeholder.

static NSColor *YCOrange(void) {
    return [NSColor colorWithSRGBRed:242.0 / 255.0 green:101.0 / 255.0 blue:34.0 / 255.0 alpha:1];
}

static NSFont *RoundedFont(CGFloat size, NSFontWeight weight) {
    NSFont *system = [NSFont systemFontOfSize:size weight:weight];
    NSFontDescriptor *rounded = [system.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    if (!rounded) rounded = system.fontDescriptor;
    NSDictionary *feature = @{
        NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
        NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector),
    };
    NSFontDescriptor *tabular = [rounded fontDescriptorByAddingAttributes:@{
        NSFontFeatureSettingsAttribute: @[feature],
    }];
    return [NSFont fontWithDescriptor:tabular size:size] ?: system;
}

#pragma mark - Store

static NSDate *PlaceholderTarget(void) {
    // Tuesday, March 16, 2027, 10:00 AM Pacific. Not an official YC time.
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
    NSDateComponents *parts = [NSDateComponents new];
    parts.year = 2027;
    parts.month = 3;
    parts.day = 16;
    parts.hour = 10;
    parts.minute = 0;
    return [calendar dateFromComponents:parts];
}

static NSDate *StoreTarget(void) {
    double stamp = [NSUserDefaults.standardUserDefaults doubleForKey:@"target"];
    return stamp > 0 ? [NSDate dateWithTimeIntervalSince1970:stamp] : PlaceholderTarget();
}

static void StoreSetTarget(NSDate *date) {
    [NSUserDefaults.standardUserDefaults setDouble:date.timeIntervalSince1970 forKey:@"target"];
}

static NSString *StoreLabel(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:@"label"];
    if (!stored) return @"Y";
    NSString *trimmed = [[NSUserDefaults.standardUserDefaults stringForKey:@"label"]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return @"Y";
    return trimmed.length > 12 ? [trimmed substringToIndex:12] : trimmed;
}

static void StoreSetLabel(NSString *label) {
    NSString *trimmed = [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) trimmed = @"Y";
    if (trimmed.length > 12) trimmed = [trimmed substringToIndex:12];
    [NSUserDefaults.standardUserDefaults setObject:trimmed forKey:@"label"];
}

static BOOL StoreConfirmed(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:@"confirmed"];
}

static void StoreSetConfirmed(BOOL value) {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:@"confirmed"];
}

static BOOL StoreDismissedSetup(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:@"dismissedSetup"];
}

static void StoreSetDismissedSetup(BOOL value) {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:@"dismissedSetup"];
}

static BOOL StoreWantsLogin(void) {
    if ([NSUserDefaults.standardUserDefaults objectForKey:@"wantsLogin"] == nil) return YES;
    return [NSUserDefaults.standardUserDefaults boolForKey:@"wantsLogin"];
}

static void StoreSetWantsLogin(BOOL value) {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:@"wantsLogin"];
}

static const int kMinDecimals = 0;
static const int kMaxDecimals = 7;
static const int kDefaultDecimals = 7;

static int ClampDecimals(int value) {
    if (value < kMinDecimals) return kMinDecimals;
    if (value > kMaxDecimals) return kMaxDecimals;
    return value;
}

static int StoreDecimals(void) {
    if ([NSUserDefaults.standardUserDefaults objectForKey:@"decimals"] == nil) return kDefaultDecimals;
    return ClampDecimals((int)[NSUserDefaults.standardUserDefaults integerForKey:@"decimals"]);
}

static void StoreSetDecimals(int value) {
    [NSUserDefaults.standardUserDefaults setInteger:ClampDecimals(value) forKey:@"decimals"];
}

#pragma mark - Formatting

static long long DayScale(int decimals) {
    long long scale = 1;
    for (int i = 0; i < decimals; i++) scale *= 10LL;
    return scale;
}

/// Days remaining, rounded to `decimals` places.
static void RoundDays(NSTimeInterval remaining, int decimals, long long *whole, long long *frac) {
    long long scale = DayScale(ClampDecimals(decimals));
    long long scaled = 0;
    if (remaining > 0) {
        scaled = llround(remaining / 86400.0 * (double)scale);
        if (scaled < 0) scaled = 0;
    }
    *whole = scaled / scale;
    *frac = scaled % scale;
}

static NSString *DaysNumber(long long whole, long long frac, int decimals) {
    decimals = ClampDecimals(decimals);
    if (decimals <= 0) return [NSString stringWithFormat:@"%lld", whole];
    NSString *format = [NSString stringWithFormat:@"%%lld.%%0%dlld", decimals];
    return [NSString stringWithFormat:format, whole, frac];
}

static NSString *StickerText(NSTimeInterval remaining, NSString *label, int decimals) {
    NSString *mark = label.length ? label : @"Y";
    if (remaining <= 0) return [NSString stringWithFormat:@"%@  DEMO DAY", mark];
    if (remaining < 48 * 3600) {
        int total = (int)remaining;
        return [NSString stringWithFormat:@"%@  %02d:%02d:%02d", mark, total / 3600, (total % 3600) / 60, total % 60];
    }
    long long whole, frac;
    RoundDays(remaining, decimals, &whole, &frac);
    return [NSString stringWithFormat:@"%@  %@d", mark, DaysNumber(whole, frac, decimals)];
}

static NSString *FractionText(NSTimeInterval remaining, int decimals) {
    if (remaining <= 0) return @"Demo Day";
    long long whole, frac;
    RoundDays(remaining, decimals, &whole, &frac);
    return DaysNumber(whole, frac, decimals);
}

static NSString *BreakdownText(NSTimeInterval remaining) {
    if (remaining <= 0) return @"It's time.";
    int total = (int)remaining;
    int days = total / 86400;
    int hours = (total % 86400) / 3600;
    int minutes = (total % 3600) / 60;
    int seconds = total % 60;
    if (days > 0) {
        return [NSString stringWithFormat:@"%dd   %02dh   %02dm   %02ds", days, hours, minutes, seconds];
    }
    return [NSString stringWithFormat:@"%02dh   %02dm   %02ds", hours, minutes, seconds];
}

static NSString *TargetLine(NSDate *date) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = @"EEEE, MMMM d, yyyy  ·  h:mm a zzz";
    return [formatter stringFromDate:date];
}

static NSImage *MakeSticker(NSString *text) {
    CGFloat bar = NSStatusBar.systemStatusBar.thickness;
    CGFloat height = MIN(22, MAX(16, bar - 6));
    NSFont *font = RoundedFont(MIN(13, round(height * 0.62)), NSFontWeightBold);
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSKernAttributeName: @(-0.25),
    };
    NSSize textSize = [text sizeWithAttributes:attributes];
    CGFloat width = ceil(textSize.width + height * 0.85);
    NSSize size = NSMakeSize(width, height);

    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSRect pill = NSInsetRect(rect, 0.25, 0.25);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:height * 0.28 yRadius:height * 0.28];
        [YCOrange() setFill];
        [path fill];
        NSRect textRect = NSMakeRect(
            (rect.size.width - textSize.width) / 2,
            (rect.size.height - textSize.height) / 2 - 0.5,
            textSize.width,
            textSize.height
        );
        [text drawInRect:textRect withAttributes:attributes];
        return YES;
    }];
    image.template = NO;
    image.accessibilityDescription = [NSString stringWithFormat:@"Demo Day %@", text];
    return image;
}

static void SyncLoginItem(void) {
    SMAppService *service = SMAppService.mainAppService;
    if (!StoreWantsLogin()) return;
    if (service.status == SMAppServiceStatusEnabled) return;
    NSError *error = nil;
    [service registerAndReturnError:&error];
}

#pragma mark - Views

@interface OrangeMark : NSView
@end

@implementation OrangeMark

- (NSSize)intrinsicContentSize {
    return NSMakeSize(28, 28);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 yRadius:6];
    [YCOrange() setFill];
    [path fill];
    NSString *text = @"Y";
    NSDictionary *attributes = @{
        NSFontAttributeName: RoundedFont(16, NSFontWeightBold),
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    NSSize size = [text sizeWithAttributes:attributes];
    [text drawAtPoint:NSMakePoint((self.bounds.size.width - size.width) / 2,
                                  (self.bounds.size.height - size.height) / 2 - 1)
        withAttributes:attributes];
}

@end

@interface PopoverController : NSViewController
@property (nonatomic, strong) NSTextField *big;
@property (nonatomic, strong) NSTextField *unit;
@property (nonatomic, strong) NSTextField *breakdown;
@property (nonatomic, strong) NSTextField *dateLabel;
@property (nonatomic, strong) NSTextField *note;
@property (nonatomic, strong) NSButton *login;
@property (nonatomic, strong) NSStackView *stack;
@property (nonatomic, copy) void (^onSetDate)(void);
@end

@implementation PopoverController

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 292, 280)];
    self.view = root;

    self.big = [NSTextField labelWithString:@"—"];
    self.big.font = RoundedFont(42, NSFontWeightBold);
    self.big.textColor = NSColor.labelColor;
    self.big.maximumNumberOfLines = 1;
    self.big.lineBreakMode = NSLineBreakByClipping;
    [self.big setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

    self.unit = [NSTextField labelWithString:@"days"];
    self.unit.font = RoundedFont(13, NSFontWeightSemibold);
    self.unit.textColor = YCOrange();

    self.breakdown = [NSTextField labelWithString:@""];
    self.breakdown.font = RoundedFont(13, NSFontWeightMedium);
    self.breakdown.textColor = NSColor.labelColor;

    self.dateLabel = [NSTextField wrappingLabelWithString:@""];
    self.dateLabel.font = RoundedFont(12, NSFontWeightRegular);
    self.dateLabel.textColor = NSColor.secondaryLabelColor;
    self.dateLabel.maximumNumberOfLines = 2;
    self.dateLabel.preferredMaxLayoutWidth = 256;

    self.note = [NSTextField wrappingLabelWithString:@"Placeholder date. YC hasn't posted the W27 Demo Day time."];
    self.note.font = RoundedFont(11, NSFontWeightMedium);
    self.note.textColor = NSColor.secondaryLabelColor;
    self.note.maximumNumberOfLines = 3;
    self.note.preferredMaxLayoutWidth = 256;

    NSTextField *kicker = [NSTextField labelWithString:@"DEMO DAY"];
    kicker.font = RoundedFont(12, NSFontWeightBold);
    kicker.textColor = YCOrange();
    NSTextField *batch = [NSTextField labelWithString:@"Winter 2027"];
    batch.font = RoundedFont(12, NSFontWeightMedium);
    batch.textColor = NSColor.secondaryLabelColor;

    NSStackView *titles = [NSStackView stackViewWithViews:@[kicker, batch]];
    titles.orientation = NSUserInterfaceLayoutOrientationVertical;
    titles.alignment = NSLayoutAttributeLeading;
    titles.spacing = 1;

    NSStackView *header = [NSStackView stackViewWithViews:@[[OrangeMark new], titles]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 10;

    NSButton *setDate = [NSButton buttonWithTitle:@"Set date…" target:self action:@selector(setDate:)];
    setDate.bezelStyle = NSBezelStyleRounded;
    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quit:)];
    quit.bezelStyle = NSBezelStyleRounded;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[setDate, quit]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.distribution = NSStackViewDistributionFillEqually;

    self.login = [NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];
    self.login.font = RoundedFont(12, NSFontWeightRegular);

    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;

    self.stack = [NSStackView stackViewWithViews:@[
        header, self.big, self.unit, self.breakdown, self.dateLabel, self.note, line, buttons, self.login,
    ]];
    self.stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stack.alignment = NSLayoutAttributeLeading;
    self.stack.spacing = 8;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stack setCustomSpacing:12 afterView:header];
    [self.stack setCustomSpacing:2 afterView:self.big];
    [self.stack setCustomSpacing:2 afterView:self.breakdown];
    [self.stack setCustomSpacing:14 afterView:self.note];
    [self.stack setCustomSpacing:12 afterView:line];

    [root addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],
        [self.stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],
        [self.stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:16],
        [buttons.widthAnchor constraintEqualToAnchor:self.stack.widthAnchor],
        [line.widthAnchor constraintEqualToAnchor:self.stack.widthAnchor],
    ]];
}

- (void)applyRemaining:(NSTimeInterval)remaining {
    if (remaining <= 0) {
        self.big.font = RoundedFont(32, NSFontWeightBold);
        self.big.stringValue = @"Demo Day";
        self.unit.stringValue = @"now";
        self.breakdown.stringValue = @"The countdown is over.";
    } else {
        NSString *fraction = FractionText(remaining, StoreDecimals());
        CGFloat pointSize = 42;
        NSFont *font = RoundedFont(pointSize, NSFontWeightBold);
        CGFloat width = [fraction sizeWithAttributes:@{NSFontAttributeName: font}].width;
        if (width > 250) {
            pointSize = floor(42.0 * 250.0 / width);
            if (pointSize < 20) pointSize = 20;
            font = RoundedFont(pointSize, NSFontWeightBold);
        }
        self.big.font = font;
        self.big.stringValue = fraction;
        self.unit.stringValue = @"days";
        self.breakdown.stringValue = BreakdownText(remaining);
    }
    self.dateLabel.stringValue = TargetLine(StoreTarget());
    self.note.hidden = StoreConfirmed();
    switch (SMAppService.mainAppService.status) {
        case SMAppServiceStatusEnabled:
            self.login.state = NSControlStateValueOn;
            break;
        case SMAppServiceStatusRequiresApproval:
            self.login.state = NSControlStateValueMixed;
            break;
        default:
            self.login.state = NSControlStateValueOff;
            break;
    }
    [self.view layoutSubtreeIfNeeded];
    CGFloat height = self.stack.fittingSize.height + 32;
    if (height < 260) height = 260;
    self.preferredContentSize = NSMakeSize(292, height);
}

- (void)setDate:(id)sender {
    if (self.onSetDate) self.onSetDate();
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (void)toggleLogin:(NSButton *)sender {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL turnOn = sender.state != NSControlStateValueOff;
    if (turnOn) {
        StoreSetWantsLogin(YES);
        if (service.status != SMAppServiceStatusEnabled) {
            [service registerAndReturnError:&error];
        }
        if (service.status == SMAppServiceStatusRequiresApproval) {
            [SMAppService openSystemSettingsLoginItems];
        }
    } else {
        StoreSetWantsLogin(NO);
        if (service.status == SMAppServiceStatusEnabled || service.status == SMAppServiceStatusRequiresApproval) {
            [service unregisterAndReturnError:&error];
        }
    }
    if (error && service.status != SMAppServiceStatusEnabled && service.status != SMAppServiceStatusRequiresApproval) {
        [NSApp activate];
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Couldn't update the login item";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    }
    [self applyRemaining:StoreTarget().timeIntervalSinceNow];
}

@end

@class SettingsController;

@interface DecimalsStepper : NSStepper
@property (nonatomic, weak) SettingsController *owner;
@end

@interface SettingsController : NSWindowController <NSWindowDelegate, NSTextFieldDelegate>
@property (nonatomic, copy) void (^onSave)(void);
@property (nonatomic, strong) NSDatePicker *picker;
@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, strong) NSTextField *decimalsField;
@property (nonatomic, strong) NSStepper *decimalsStepper;
@property (nonatomic, strong) NSTextField *preview;
@property (nonatomic) BOOL didSave;
@property (nonatomic) BOOL steppingDecimals;
@end

@implementation DecimalsStepper

- (void)mouseDown:(NSEvent *)event {
    self.owner.steppingDecimals = YES;
    [super mouseDown:event];
    self.owner.steppingDecimals = NO;
}

@end

@implementation SettingsController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 320)
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    window.title = @"Demo Day";
    window.level = NSFloatingWindowLevel;
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        window.delegate = self;
        [self build];
        [window center];
    }
    return self;
}

- (void)windowWillClose:(NSNotification *)notification {
    if (!self.didSave && !StoreConfirmed()) StoreSetDismissedSetup(YES);
}

- (NSTextField *)caption:(NSString *)text {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = RoundedFont(11, NSFontWeightSemibold);
    field.textColor = NSColor.secondaryLabelColor;
    return field;
}

- (void)build {
    NSView *content = self.window.contentView;

    NSTextField *intro = [NSTextField wrappingLabelWithString:@"The orange sticker in the menu bar counts down to this moment."];
    intro.font = RoundedFont(13, NSFontWeightMedium);
    intro.textColor = NSColor.labelColor;
    intro.preferredMaxLayoutWidth = 392;

    NSTextField *note = [NSTextField wrappingLabelWithString:@"YC hasn't posted the W27 Demo Day time. March 16, 2027 at 10:00 AM Pacific is a placeholder."];
    note.font = RoundedFont(12, NSFontWeightRegular);
    note.textColor = NSColor.secondaryLabelColor;
    note.preferredMaxLayoutWidth = 392;
    note.hidden = StoreConfirmed();

    self.picker = [NSDatePicker new];
    self.picker.datePickerStyle = NSDatePickerStyleTextField;
    self.picker.presentsCalendarOverlay = YES;
    self.picker.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    self.picker.dateValue = StoreTarget();
    self.picker.font = RoundedFont(13, NSFontWeightMedium);
    self.picker.target = self;
    self.picker.action = @selector(refreshPreview);

    self.labelField = [NSTextField textFieldWithString:StoreLabel()];
    self.labelField.placeholderString = @"Y";
    self.labelField.font = RoundedFont(13, NSFontWeightSemibold);
    self.labelField.alignment = NSTextAlignmentCenter;
    self.labelField.target = self;
    self.labelField.action = @selector(refreshPreview);

    self.preview = [NSTextField labelWithString:@""];
    self.preview.font = RoundedFont(13, NSFontWeightBold);
    self.preview.textColor = YCOrange();

    NSTextField *hint = [NSTextField labelWithString:@"Sits on the left of the countdown. Y is the default."];
    hint.font = RoundedFont(11, NSFontWeightRegular);
    hint.textColor = NSColor.tertiaryLabelColor;

    self.decimalsField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%d", StoreDecimals()]];
    self.decimalsField.font = RoundedFont(13, NSFontWeightSemibold);
    self.decimalsField.alignment = NSTextAlignmentCenter;
    self.decimalsField.delegate = self;
    self.decimalsField.target = self;
    self.decimalsField.action = @selector(decimalsEdited:);
    DecimalsStepper *decimalsStepper = [DecimalsStepper new];
    decimalsStepper.owner = self;
    self.decimalsStepper = decimalsStepper;
    self.decimalsStepper.minValue = kMinDecimals;
    self.decimalsStepper.maxValue = kMaxDecimals;
    self.decimalsStepper.increment = 1;
    self.decimalsStepper.valueWraps = NO;
    self.decimalsStepper.integerValue = StoreDecimals();
    self.decimalsStepper.target = self;
    self.decimalsStepper.action = @selector(stepDecimals:);
    NSStackView *decimalsRow = [NSStackView stackViewWithViews:@[self.decimalsField, self.decimalsStepper]];
    decimalsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    decimalsRow.alignment = NSLayoutAttributeCenterY;
    decimalsRow.spacing = 6;

    NSTextField *decimalsHint = [NSTextField labelWithString:@"Digits after the decimal on the day count. 7 is the default."];
    decimalsHint.font = RoundedFont(11, NSFontWeightRegular);
    decimalsHint.textColor = NSColor.tertiaryLabelColor;

    NSButton *cancel = [NSButton buttonWithTitle:(StoreConfirmed() ? @"Cancel" : @"Not now")
                                          target:self
                                          action:@selector(notNow:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    NSButton *save = [NSButton buttonWithTitle:@"Save" target:self action:@selector(save:)];
    save.bezelStyle = NSBezelStyleRounded;
    save.keyEquivalent = @"\r";

    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[cancel, save]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;
    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *bottom = [NSStackView stackViewWithViews:@[spacer, buttonRow]];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        intro,
        note,
        [self caption:@"Counts down to"],
        self.picker,
        [self caption:@"Sticker label"],
        self.labelField,
        hint,
        [self caption:@"Decimals"],
        decimalsRow,
        decimalsHint,
        self.preview,
        bottom,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:14 afterView:intro];
    [stack setCustomSpacing:4 afterView:stack.arrangedSubviews[2]];
    [stack setCustomSpacing:12 afterView:self.picker];
    [stack setCustomSpacing:4 afterView:stack.arrangedSubviews[4]];
    [stack setCustomSpacing:2 afterView:self.labelField];
    [stack setCustomSpacing:12 afterView:hint];
    [stack setCustomSpacing:4 afterView:stack.arrangedSubviews[7]];
    [stack setCustomSpacing:2 afterView:decimalsRow];
    [stack setCustomSpacing:14 afterView:decimalsHint];
    [stack setCustomSpacing:16 afterView:self.preview];

    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18],
        [stack.widthAnchor constraintEqualToConstant:396],
        [bottom.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.labelField.widthAnchor constraintEqualToConstant:88],
        [self.decimalsField.widthAnchor constraintEqualToConstant:56],
    ]];

    [self refreshPreview];
    [content layoutSubtreeIfNeeded];
    [self.window setContentSize:content.fittingSize];
}

- (void)setDecimalsControls:(int)value {
    value = ClampDecimals(value);
    self.decimalsField.stringValue = [NSString stringWithFormat:@"%d", value];
    self.decimalsStepper.integerValue = value;
}

- (void)stepDecimals:(NSStepper *)sender {
    self.steppingDecimals = YES;
    [self setDecimalsControls:(int)sender.integerValue];
    [self refreshPreview];
    self.steppingDecimals = NO;
}

- (void)decimalsEdited:(id)sender {
    [self setDecimalsControls:(int)self.decimalsField.integerValue];
    [self refreshPreview];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object != self.decimalsField) return;
    if (self.decimalsField.stringValue.length == 0) {
        self.decimalsStepper.integerValue = kMinDecimals;
        [self refreshPreview];
        return;
    }
    int value = (int)self.decimalsField.integerValue;
    if (value < kMinDecimals || value > kMaxDecimals) {
        [self setDecimalsControls:value];
    } else {
        self.decimalsStepper.integerValue = value;
    }
    [self refreshPreview];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object != self.decimalsField) return;
    // A click on the stepper already wrote the new value. Don't put the old digits back.
    if (self.steppingDecimals || self.window.firstResponder == self.decimalsStepper) {
        [self refreshPreview];
        return;
    }
    [self setDecimalsControls:(int)self.decimalsField.integerValue];
    [self refreshPreview];
}

- (void)refreshPreview {
    NSString *trimmed = [self.labelField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) trimmed = @"Y";
    NSTimeInterval remaining = self.picker.dateValue.timeIntervalSinceNow;
    int decimals = self.decimalsField ? ClampDecimals((int)self.decimalsField.integerValue) : StoreDecimals();
    self.preview.stringValue = [NSString stringWithFormat:@"Sticker reads   %@", StickerText(remaining, trimmed, decimals)];
}

- (void)save:(id)sender {
    [self.window endEditingFor:nil];
    [self setDecimalsControls:(int)self.decimalsField.integerValue];
    StoreSetLabel(self.labelField.stringValue);
    StoreSetDecimals((int)self.decimalsField.integerValue);
    StoreSetTarget(self.picker.dateValue);
    StoreSetConfirmed(YES);
    self.didSave = YES;
    if (self.onSave) self.onSave();
    [self.window close];
}

- (void)notNow:(id)sender {
    StoreSetDismissedSetup(YES);
    [self.window close];
}

@end

#pragma mark - App

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) PopoverController *popoverController;
@property (nonatomic, strong) SettingsController *settings;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *lastSticker;
@property (nonatomic) BOOL quiet;
@property (nonatomic) BOOL showPopover;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSArray<NSRunningApplication *> *others =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.demoday.countdown"];
    for (NSRunningApplication *app in others) {
        if (app.processIdentifier != getpid()) {
            [NSApp terminate:nil];
            return;
        }
    }

    self.quiet = [NSProcessInfo.processInfo.arguments containsObject:@"--quiet"];
    self.showPopover = [NSProcessInfo.processInfo.arguments containsObject:@"--show"];
    self.lastSticker = @"";

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.target = self;
    button.action = @selector(togglePopover:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];

    self.popoverController = [PopoverController new];
    __weak AppDelegate *weakSelf = self;
    self.popoverController.onSetDate = ^{
        [weakSelf openSettings:nil];
    };

    self.popover = [NSPopover new];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = YES;
    self.popover.contentViewController = self.popoverController;

    SyncLoginItem();
    [self tick];

    // 7th decimal of a day moves every ~9ms, so the sticker has to tick faster than once a second.
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf tick];
    }];
    self.timer.tolerance = 0.01;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];

    if (self.showPopover) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf presentPopover];
            [weakSelf dumpWindows];
        });
    } else if (!self.quiet && !StoreConfirmed() && !StoreDismissedSetup()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf openSettings:nil];
        });
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf dumpWindows];
    });
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)tick {
    NSTimeInterval remaining = StoreTarget().timeIntervalSinceNow;
    NSString *text = StickerText(remaining, StoreLabel(), StoreDecimals());
    if (![text isEqualToString:self.lastSticker]) {
        self.lastSticker = text;
        NSImage *image = MakeSticker(text);
        NSStatusBarButton *button = self.statusItem.button;
        button.image = image;
        button.image.template = NO;
    }
    NSString *tip = remaining <= 0 ? @"Demo Day" : [NSString stringWithFormat:@"%@ until Demo Day", BreakdownText(remaining)];
    self.statusItem.button.toolTip = tip;
    self.statusItem.button.accessibilityLabel = tip;
    if (self.popover.isShown) {
        [self.popoverController applyRemaining:remaining];
        NSSize size = self.popoverController.preferredContentSize;
        if (fabs(self.popover.contentSize.height - size.height) > 1 || fabs(self.popover.contentSize.width - size.width) > 1) {
            self.popover.contentSize = size;
        }
    }
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover performClose:sender];
        return;
    }
    __weak AppDelegate *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf presentPopover];
    });
}

- (void)presentPopover {
    NSStatusBarButton *button = self.statusItem.button;
    if (!button) return;
    NSTimeInterval remaining = StoreTarget().timeIntervalSinceNow;
    [self.popoverController applyRemaining:remaining];
    self.popover.contentSize = self.popoverController.preferredContentSize;
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
    [NSApp activate];
}

- (void)openSettings:(id)sender {
    [self.popover performClose:sender];
    SettingsController *controller = [SettingsController new];
    __weak AppDelegate *weakSelf = self;
    controller.onSave = ^{
        weakSelf.lastSticker = @"";
        [weakSelf tick];
    };
    self.settings = controller;
    [controller showWindow:nil];
    [NSApp activate];
    [controller.window makeKeyAndOrderFront:nil];
}

- (void)dumpWindows {
    if (!self.quiet && !self.showPopover) return;
    NSWindow *statusWindow = self.statusItem.button.window;
    if (statusWindow) {
        fprintf(stderr, "STATUS %ld %s\n", (long)statusWindow.windowNumber, NSStringFromRect(statusWindow.frame).UTF8String);
    }
    for (NSWindow *window in NSApp.windows) {
        if (!window.isVisible) continue;
        fprintf(stderr, "WIN %ld %s\n", (long)window.windowNumber, NSStringFromRect(window.frame).UTF8String);
    }
    NSTimeInterval remaining = StoreTarget().timeIntervalSinceNow;
    fprintf(stderr, "STICKER %s\n", StickerText(remaining, StoreLabel(), StoreDecimals()).UTF8String);
    fflush(stderr);
}

@end

static AppDelegate *gDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        gDelegate = [AppDelegate new];
        app.delegate = gDelegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
