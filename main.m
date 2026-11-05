#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

#define IS_IOS7 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0)

static UIColor *RGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static UIColor *Accent(void) { return RGB(255, 106, 136); }

// ---------- File helpers ----------
static NSArray *PlayableExts(void) { return @[@"mp4", @"m4v", @"mov", @"3gp"]; }
static NSArray *OtherExts(void) {
    return @[@"mkv", @"avi", @"flv", @"wmv", @"webm", @"mpg", @"mpeg", @"ts", @"ogv", @"rmvb"];
}

static NSString *DocsPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
}
static NSString *CachesPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
}
static NSString *ThumbDir(void) {
    NSString *d = [CachesPath() stringByAppendingPathComponent:@"thumbs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

static NSString *Bytes(unsigned long long b) {
    double v = (double)b;
    if (v >= 1073741824.0) return [NSString stringWithFormat:@"%.1f GB", v / 1073741824.0];
    if (v >= 1048576.0) return [NSString stringWithFormat:@"%.0f MB", v / 1048576.0];
    return [NSString stringWithFormat:@"%.0f KB", v / 1024.0];
}

static NSString *Dur(double s) {
    if (s <= 0 || isnan(s) || isinf(s)) return nil;
    int t = (int)(s + 0.5);
    int h = t / 3600, m = (t % 3600) / 60, sec = t % 60;
    if (h > 0) return [NSString stringWithFormat:@"%d:%02d:%02d", h, m, sec];
    return [NSString stringWithFormat:@"%d:%02d", m, sec];
}

static UIImage *PlayBadge(void) {
    static UIImage *img = nil;
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(28, 28), NO, 0);
    CGContextRef g = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(g, [UIColor colorWithWhite:0 alpha:0.55].CGColor);
    CGContextFillEllipseInRect(g, CGRectMake(0, 0, 28, 28));
    CGContextSetFillColorWithColor(g, [UIColor whiteColor].CGColor);
    CGContextMoveToPoint(g, 11, 8);
    CGContextAddLineToPoint(g, 11, 20);
    CGContextAddLineToPoint(g, 21, 14);
    CGContextClosePath(g);
    CGContextFillPath(g);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// ---------- Video model ----------
@interface Video : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, assign) BOOL playable;
@property (nonatomic, assign) double duration;
@end
@implementation Video
@end

// ---------- Row ----------
@interface VideoCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UIImageView *playBadge;
@property (nonatomic, strong) UILabel *titleL;
@property (nonatomic, strong) UILabel *subL;
@end

@implementation VideoCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (self) {
        self.thumb = [[UIImageView alloc] init];
        self.thumb.contentMode = UIViewContentModeScaleAspectFill;
        self.thumb.clipsToBounds = YES;
        self.thumb.layer.cornerRadius = 6;
        self.thumb.backgroundColor = RGB(30, 32, 44);
        [self.contentView addSubview:self.thumb];

        self.playBadge = [[UIImageView alloc] initWithImage:PlayBadge()];
        [self.contentView addSubview:self.playBadge];

        self.titleL = [[UILabel alloc] init];
        self.titleL.backgroundColor = [UIColor clearColor];
        self.titleL.textColor = [UIColor whiteColor];
        self.titleL.font = [UIFont boldSystemFontOfSize:15];
        self.titleL.numberOfLines = 2;
        [self.contentView addSubview:self.titleL];

        self.subL = [[UILabel alloc] init];
        self.subL.backgroundColor = [UIColor clearColor];
        self.subL.font = [UIFont systemFontOfSize:12];
        [self.contentView addSubview:self.subL];

        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = RGB(38, 40, 54);
        self.selectedBackgroundView = sel;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat w = self.contentView.bounds.size.width;
    self.thumb.frame = CGRectMake(12, (h - 61) / 2, 108, 61);
    self.playBadge.frame = CGRectMake(12 + (108 - 28) / 2, (h - 28) / 2, 28, 28);
    CGFloat tx = 132;
    self.titleL.frame = CGRectMake(tx, 10, MAX(w - tx - 10, 40), 38);
    self.subL.frame = CGRectMake(tx, 52, MAX(w - tx - 10, 40), 18);
}
@end

// ---------- Library screen ----------
@interface LibraryVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate, NSURLConnectionDataDelegate>
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UILabel *titleL;
@property (nonatomic, strong) UILabel *statsL;
@property (nonatomic, strong) UIButton *editBtn;
@property (nonatomic, strong) UIButton *addBtn;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *emptyL;
@property (nonatomic, strong) NSMutableArray *videos;
@property (nonatomic, strong) NSMutableDictionary *thumbs;
@property (nonatomic, strong) NSMutableSet *requested;
@property (nonatomic, strong) NSOperationQueue *thumbQueue;

// download
@property (nonatomic, strong) UIView *dlBar;
@property (nonatomic, strong) UILabel *dlLabel;
@property (nonatomic, strong) UIView *dlTrack;
@property (nonatomic, strong) UIView *dlFill;
@property (nonatomic, strong) UIButton *dlCancel;
@property (nonatomic, strong) NSURLConnection *conn;
@property (nonatomic, strong) NSFileHandle *fh;
@property (nonatomic, copy) NSString *tmpPath;
@property (nonatomic, copy) NSString *finalName;
@property (nonatomic, assign) long long expected;
@property (nonatomic, assign) long long received;
@property (nonatomic, assign) BOOL downloading;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@end

@implementation LibraryVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = RGB(14, 15, 20);
    self.videos = [NSMutableArray array];
    self.thumbs = [NSMutableDictionary dictionary];
    self.requested = [NSMutableSet set];
    self.thumbQueue = [[NSOperationQueue alloc] init];
    self.thumbQueue.maxConcurrentOperationCount = 1;
    self.bgTask = UIBackgroundTaskInvalid;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = RGB(14, 15, 20);
    self.table.separatorColor = RGB(34, 36, 48);
    self.table.rowHeight = 80;
    [self.view addSubview:self.table];

    self.emptyL = [[UILabel alloc] init];
    self.emptyL.backgroundColor = [UIColor clearColor];
    self.emptyL.textColor = RGB(130, 135, 150);
    self.emptyL.font = [UIFont systemFontOfSize:15];
    self.emptyL.textAlignment = NSTextAlignmentCenter;
    self.emptyL.numberOfLines = 0;
    self.emptyL.text = @"No videos yet\n\nTap + to add from a link, or copy videos in with 3uTools (tap + then How to add videos).";
    [self.view addSubview:self.emptyL];

    // download bar
    self.dlBar = [[UIView alloc] init];
    self.dlBar.backgroundColor = RGB(28, 32, 52);
    self.dlBar.hidden = YES;
    [self.view addSubview:self.dlBar];

    self.dlLabel = [[UILabel alloc] init];
    self.dlLabel.backgroundColor = [UIColor clearColor];
    self.dlLabel.textColor = [UIColor whiteColor];
    self.dlLabel.font = [UIFont systemFontOfSize:13];
    self.dlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.dlBar addSubview:self.dlLabel];

    self.dlTrack = [[UIView alloc] init];
    self.dlTrack.backgroundColor = RGB(50, 54, 74);
    self.dlTrack.layer.cornerRadius = 2;
    [self.dlBar addSubview:self.dlTrack];

    self.dlFill = [[UIView alloc] init];
    self.dlFill.backgroundColor = Accent();
    self.dlFill.layer.cornerRadius = 2;
    [self.dlTrack addSubview:self.dlFill];

    self.dlCancel = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.dlCancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.dlCancel setTitleColor:Accent() forState:UIControlStateNormal];
    self.dlCancel.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.dlCancel addTarget:self action:@selector(cancelTap) forControlEvents:UIControlEventTouchUpInside];
    [self.dlBar addSubview:self.dlCancel];

    // header
    self.bar = [[UIView alloc] init];
    self.bar.backgroundColor = RGB(24, 26, 34);
    [self.view addSubview:self.bar];

    self.titleL = [[UILabel alloc] init];
    self.titleL.backgroundColor = [UIColor clearColor];
    self.titleL.textColor = [UIColor whiteColor];
    self.titleL.font = [UIFont boldSystemFontOfSize:26];
    self.titleL.text = @"Library";
    [self.bar addSubview:self.titleL];

    self.statsL = [[UILabel alloc] init];
    self.statsL.backgroundColor = [UIColor clearColor];
    self.statsL.textColor = RGB(130, 135, 150);
    self.statsL.font = [UIFont systemFontOfSize:12];
    [self.bar addSubview:self.statsL];

    self.editBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.editBtn setTitle:@"Edit" forState:UIControlStateNormal];
    [self.editBtn setTitleColor:Accent() forState:UIControlStateNormal];
    self.editBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.editBtn addTarget:self action:@selector(editTap) forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:self.editBtn];

    self.addBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.addBtn setTitle:@"+" forState:UIControlStateNormal];
    [self.addBtn setTitleColor:Accent() forState:UIControlStateNormal];
    self.addBtn.titleLabel.font = [UIFont systemFontOfSize:32];
    [self.addBtn addTarget:self action:@selector(addTap) forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:self.addBtn];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadLibrary)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [self reloadLibrary];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = IS_IOS7 ? 20 : 0;
    CGFloat barH = top + 64;

    self.bar.frame = CGRectMake(0, 0, b.size.width, barH);
    self.titleL.frame = CGRectMake(16, top + 6, b.size.width - 150, 32);
    self.statsL.frame = CGRectMake(16, top + 40, b.size.width - 32, 16);
    self.editBtn.frame = CGRectMake(b.size.width - 136, top + 8, 66, 34);
    self.addBtn.frame = CGRectMake(b.size.width - 64, top + 4, 54, 40);

    CGFloat y = barH;
    self.dlBar.hidden = !self.downloading;
    if (self.downloading) {
        self.dlBar.frame = CGRectMake(0, y, b.size.width, 52);
        self.dlLabel.frame = CGRectMake(14, 7, b.size.width - 100, 18);
        self.dlCancel.frame = CGRectMake(b.size.width - 80, 2, 70, 30);
        self.dlTrack.frame = CGRectMake(14, 36, b.size.width - 28, 4);
        [self updateFill];
        y += 52;
    }
    self.table.frame = CGRectMake(0, y, b.size.width, b.size.height - y);
    self.emptyL.frame = CGRectMake(28, y + 60, b.size.width - 56, 140);
}

// ---------- Library ----------
- (NSString *)durKey:(Video *)v {
    return [NSString stringWithFormat:@"%@|%llu", [v.path lastPathComponent], v.size];
}

- (NSString *)thumbName:(Video *)v {
    return [NSString stringWithFormat:@"%08lx_%llu.jpg", (unsigned long)[[v.path lastPathComponent] hash], v.size];
}

- (void)reloadLibrary {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:DocsPath() error:nil];
    NSDictionary *durs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"durations"];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."]) continue;
        NSString *ext = [[n pathExtension] lowercaseString];
        BOOL ok = [PlayableExts() containsObject:ext];
        BOOL other = [OtherExts() containsObject:ext];
        if (!ok && !other) continue;
        NSString *p = [DocsPath() stringByAppendingPathComponent:n];
        NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
        Video *v = [[Video alloc] init];
        v.path = p;
        v.playable = ok;
        v.size = [at fileSize];
        v.title = [[n stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        NSNumber *d = [durs objectForKey:[self durKey:v]];
        v.duration = d ? [d doubleValue] : 0;
        [out addObject:v];
    }
    [out sortUsingComparator:^NSComparisonResult(id a, id b) {
        Video *x = a, *y = b;
        return [[x.path lastPathComponent] compare:[y.path lastPathComponent]
                                           options:NSCaseInsensitiveSearch | NSNumericSearch];
    }];
    self.videos = out;
    [self.table reloadData];
    [self updateStats];
}

- (void)updateStats {
    unsigned long long total = 0;
    for (Video *v in self.videos) total += v.size;
    NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    unsigned long long free = [[fs objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
    NSUInteger n = self.videos.count;
    if (n == 0) {
        self.statsL.text = [NSString stringWithFormat:@"Library is empty \u00B7 %@ free", Bytes(free)];
    } else {
        self.statsL.text = [NSString stringWithFormat:@"%lu video%@ \u00B7 %@ used \u00B7 %@ free",
                            (unsigned long)n, n == 1 ? @"" : @"s", Bytes(total), Bytes(free)];
    }
    self.emptyL.hidden = (n > 0);
    self.editBtn.hidden = (n == 0);
}

// ---------- Thumbnails ----------
- (UIImage *)thumbForVideo:(Video *)v {
    UIImage *img = [self.thumbs objectForKey:v.path];
    if (img) return img;
    if (!v.playable) return nil;
    if ([self.requested containsObject:v.path]) return nil;
    [self.requested addObject:v.path];

    NSString *path = v.path;
    NSString *tpath = [ThumbDir() stringByAppendingPathComponent:[self thumbName:v]];
    NSString *dkey = [self durKey:v];

    [self.thumbQueue addOperationWithBlock:^{
        UIImage *ti = [UIImage imageWithContentsOfFile:tpath];
        NSNumber *cached = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"durations"] objectForKey:dkey];
        double dur = cached ? [cached doubleValue] : 0;
        if (!ti || !cached) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
            dur = CMTimeGetSeconds(asset.duration);
            if (!ti) {
                AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
                gen.appliesPreferredTrackTransform = YES;
                gen.maximumSize = CGSizeMake(320, 180);
                double when = (dur > 0 && !isnan(dur) && !isinf(dur)) ? MIN(dur * 0.1, 90.0) : 1.0;
                CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(when, 600) actualTime:NULL error:NULL];
                if (cg) {
                    ti = [UIImage imageWithCGImage:cg];
                    CGImageRelease(cg);
                    [UIImageJPEGRepresentation(ti, 0.8) writeToFile:tpath atomically:YES];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ti) [self.thumbs setObject:ti forKey:path];
            if (dur > 0 && !isnan(dur) && !isinf(dur)) {
                NSMutableDictionary *m = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"durations"] mutableCopy];
                if (!m) m = [NSMutableDictionary dictionary];
                [m setObject:[NSNumber numberWithDouble:dur] forKey:dkey];
                [[NSUserDefaults standardUserDefaults] setObject:m forKey:@"durations"];
            }
            [self refreshRowForPath:path duration:dur];
        });
    }];
    return nil;
}

- (void)refreshRowForPath:(NSString *)path duration:(double)dur {
    for (NSUInteger i = 0; i < self.videos.count; i++) {
        Video *v = [self.videos objectAtIndex:i];
        if ([v.path isEqualToString:path]) {
            if (dur > 0 && !isnan(dur) && !isinf(dur)) v.duration = dur;
            VideoCell *c = (VideoCell *)[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
            if (c) [self configure:c video:v];
            break;
        }
    }
}

- (void)configure:(VideoCell *)c video:(Video *)v {
    c.titleL.text = v.title;
    c.thumb.image = [self thumbForVideo:v];
    c.playBadge.hidden = !v.playable;
    if (!v.playable) {
        c.subL.textColor = RGB(255, 120, 120);
        c.subL.text = [NSString stringWithFormat:@"%@ \u00B7 can't play, convert to MP4", Bytes(v.size)];
    } else {
        c.subL.textColor = RGB(140, 146, 165);
        NSString *d = Dur(v.duration);
        c.subL.text = d ? [NSString stringWithFormat:@"%@ \u00B7 %@", Bytes(v.size), d] : Bytes(v.size);
    }
}

// ---------- Table ----------
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.videos.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    VideoCell *c = (VideoCell *)[tv dequeueReusableCellWithIdentifier:@"v"];
    if (!c) c = [[VideoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"v"];
    [self configure:c video:[self.videos objectAtIndex:ip.row]];
    return c;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    c.backgroundColor = RGB(14, 15, 20);
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    Video *v = [self.videos objectAtIndex:ip.row];
    if (!v.playable) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Can't play this file"
            message:@"iOS 6 can only play MP4, M4V or MOV videos. Convert it on your PC with HandBrake, then copy the new file in."
            delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [a show];
        return;
    }
    MPMoviePlayerViewController *mp = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:v.path]];
    [self presentMoviePlayerViewControllerAnimated:mp];
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    Video *v = [self.videos objectAtIndex:ip.row];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:v.path error:nil];
    [fm removeItemAtPath:[ThumbDir() stringByAppendingPathComponent:[self thumbName:v]] error:nil];
    [self.thumbs removeObjectForKey:v.path];
    [self.requested removeObject:v.path];
    [self.videos removeObjectAtIndex:ip.row];
    [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationLeft];
    [self updateStats];
    if (self.videos.count == 0) {
        [self.table setEditing:NO animated:YES];
        [self.editBtn setTitle:@"Edit" forState:UIControlStateNormal];
    }
}

- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip {
    return @"Remove";
}

// ---------- Buttons ----------
- (void)editTap {
    BOOL e = !self.table.editing;
    [self.table setEditing:e animated:YES];
    [self.editBtn setTitle:(e ? @"Done" : @"Edit") forState:UIControlStateNormal];
}

- (void)addTap {
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:nil delegate:self
                                          cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
                                          otherButtonTitles:@"Add from link", @"Refresh library", @"How to add videos", nil];
    s.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    [s showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)idx {
    if (idx == sheet.cancelButtonIndex || idx < 0) return;
    if (idx == 0) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Add from link"
            message:@"Paste a direct link to a video file (Dropbox and Google Drive share links work too)."
            delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Download", nil];
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        a.tag = 1;
        UITextField *tf = [a textFieldAtIndex:0];
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.placeholder = @"https://...";
        NSString *pb = [UIPasteboard generalPasteboard].string;
        if ([pb hasPrefix:@"http"]) tf.text = pb;
        [a show];
    } else if (idx == 1) {
        [self reloadLibrary];
    } else if (idx == 2) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Adding videos"
            message:@"Plug your iPod into your PC with the charger cable, open 3uTools, and copy your videos into this app's Documents folder. Then reopen this app and they show up. Only MP4, M4V and MOV videos can play."
            delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [a show];
    }
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)idx {
    if (alert.tag == 1 && idx == 1) {
        [self startDownload:[[alert textFieldAtIndex:0] text]];
    }
}

- (void)alertTitle:(NSString *)t message:(NSString *)m {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:t message:m delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
}

// ---------- Download from a link ----------
- (NSURL *)directURL:(NSString *)raw {
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) return nil;
    if (![s hasPrefix:@"http://"] && ![s hasPrefix:@"https://"]) s = [@"http://" stringByAppendingString:s];

    if ([s rangeOfString:@"dropbox.com"].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"dl=0" withString:@"dl=1"];
        if ([s rangeOfString:@"dl=1"].location == NSNotFound) {
            s = [s stringByAppendingString:([s rangeOfString:@"?"].location == NSNotFound ? @"?dl=1" : @"&dl=1")];
        }
    }
    NSRange r = [s rangeOfString:@"drive.google.com/file/d/"];
    if (r.location != NSNotFound) {
        NSString *rest = [s substringFromIndex:r.location + r.length];
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *fid = (slash.location != NSNotFound) ? [rest substringToIndex:slash.location] : rest;
        NSRange q = [fid rangeOfString:@"?"];
        if (q.location != NSNotFound) fid = [fid substringToIndex:q.location];
        s = [NSString stringWithFormat:@"https://drive.google.com/uc?export=download&id=%@", fid];
    }
    return [NSURL URLWithString:s];
}

- (void)startDownload:(NSString *)raw {
    if (self.downloading) {
        [self alertTitle:@"One at a time" message:@"Wait for the current download to finish first."];
        return;
    }
    NSURL *u = [self directURL:raw];
    if (!u) {
        [self alertTitle:@"Bad link" message:@"That doesn't look like a web link."];
        return;
    }
    self.tmpPath = [CachesPath() stringByAppendingPathComponent:@"download.part"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.tmpPath error:nil];
    [fm createFileAtPath:self.tmpPath contents:nil attributes:nil];
    self.fh = [NSFileHandle fileHandleForWritingAtPath:self.tmpPath];
    self.received = 0;
    self.expected = -1;
    self.finalName = nil;
    self.downloading = YES;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    self.dlLabel.text = @"Connecting\u2026";
    self.bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self failDownload:@"The download stopped because the app was in the background too long."];
    }];
    NSURLRequest *req = [NSURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    self.conn = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    [self.view setNeedsLayout];
}

- (void)updateFill {
    CGFloat w = self.dlTrack.bounds.size.width;
    double frac = (self.expected > 0) ? ((double)self.received / (double)self.expected) : 0;
    if (frac > 1) frac = 1;
    self.dlFill.frame = CGRectMake(0, 0, w * frac, self.dlTrack.bounds.size.height);
}

- (void)endDownloadCleanup {
    [self.fh closeFile];
    self.fh = nil;
    self.conn = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tmpPath error:nil];
    self.downloading = NO;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    [self.view setNeedsLayout];
}

- (void)failDownload:(NSString *)msg {
    if (!self.downloading) return;
    [self.conn cancel];
    [self endDownloadCleanup];
    [self alertTitle:@"Download failed" message:msg];
}

- (void)cancelTap {
    if (!self.downloading) return;
    [self.conn cancel];
    [self endDownloadCleanup];
}

- (NSString *)pickNameFor:(NSURLResponse *)r {
    NSMutableArray *cands = [NSMutableArray array];
    if (r.suggestedFilename) [cands addObject:r.suggestedFilename];
    NSString *last = [[r URL] lastPathComponent];
    if (last) {
        NSString *dec = [last stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        [cands addObject:(dec ? dec : last)];
    }
    for (NSString *n in cands) {
        NSString *ext = [[n pathExtension] lowercaseString];
        if ([PlayableExts() containsObject:ext] || [OtherExts() containsObject:ext]) {
            NSString *clean = [n stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
            clean = [clean stringByReplacingOccurrencesOfString:@":" withString:@"-"];
            return clean;
        }
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH-mm";
    return [NSString stringWithFormat:@"Video %@.mp4", [df stringFromDate:[NSDate date]]];
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r {
    if ([r isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger code = [(NSHTTPURLResponse *)r statusCode];
        if (code >= 400) {
            [self failDownload:[NSString stringWithFormat:@"The server said error %ld.", (long)code]];
            return;
        }
    }
    NSString *mime = [[r MIMEType] lowercaseString];
    if ([mime hasPrefix:@"text/"]) {
        [self failDownload:@"That link is a web page, not a video file. Use a direct download link."];
        return;
    }
    self.expected = r.expectedContentLength;
    self.finalName = [self pickNameFor:r];
    self.dlLabel.text = self.finalName;
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    [self.fh writeData:data];
    self.received += data.length;
    if (self.expected > 0) {
        self.dlLabel.text = [NSString stringWithFormat:@"%@ \u2014 %@ of %@", self.finalName, Bytes((unsigned long long)self.received), Bytes((unsigned long long)self.expected)];
    } else {
        self.dlLabel.text = [NSString stringWithFormat:@"%@ \u2014 %@", self.finalName, Bytes((unsigned long long)self.received)];
    }
    [self updateFill];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [self.fh closeFile];
    self.fh = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *name = self.finalName ? self.finalName : @"Video.mp4";
    NSString *dest = [DocsPath() stringByAppendingPathComponent:name];
    int n = 2;
    while ([fm fileExistsAtPath:dest]) {
        dest = [DocsPath() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@ (%d).%@", [name stringByDeletingPathExtension], n, [name pathExtension]]];
        n++;
    }
    NSError *err = nil;
    [fm moveItemAtPath:self.tmpPath toPath:dest error:&err];
    self.conn = nil;
    self.downloading = NO;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    [self.view setNeedsLayout];
    if (err) [self alertTitle:@"Couldn't save" message:[err localizedDescription]];
    [self reloadLibrary];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    NSString *msg = [error localizedDescription];
    if (error.code == NSURLErrorSecureConnectionFailed || error.code == NSURLErrorServerCertificateUntrusted ||
        error.code == NSURLErrorServerCertificateHasUnknownRoot || error.code == NSURLErrorServerCertificateHasBadDate) {
        msg = @"This old iOS can't make a secure connection to that site. Copy the video in with 3uTools instead.";
    }
    [self failDownload:msg];
}

// ---------- Rotation ----------
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return o != UIInterfaceOrientationPortraitUpsideDown; }

@end

// ---------- App ----------
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = RGB(14, 15, 20);
    self.window.rootViewController = [[LibraryVC alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
