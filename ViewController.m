#import "ViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Định nghĩa rõ ràng lớp ViewController tuân thủ giao thức chọn file của Apple
@interface ViewController () <UIDocumentPickerDelegate> {
    UIButton *btnSelectFile;
    UIButton *btnPlayPause;
    UILabel *lblStatus;
    UISlider *sliderSpeed;
    UILabel *lblSpeedText;
    
    NSMutableArray *gpxPoints;
    NSInteger currentPointIndex;
    BOOL isPlaying;
    dispatch_queue_t geoQueue;
    
    NSString *systemCachePath;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLayoutSubviews];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:1.0];
    
    gpxPoints = [[NSMutableArray alloc] init];
    geoQueue = dispatch_queue_create("com.omni.app.queue", DISPATCH_QUEUE_SERIAL);
    systemCachePath = @"/var/mobile/Library/Caches/com.apple.locationd/Simulation.plist";

    // --- GIAO DIỆN ĐIỀU KHIỂN ---
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, self.view.frame.size.width - 40, 40)];
    titleLabel.text = @"OMNI GPS - TROLLSTORE SYSTEM";
    titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:1.0];
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    btnSelectFile = [UIButton buttonWithType:UIButtonTypeCustom];
    btnSelectFile.frame = CGRectMake(30, 130, self.view.frame.size.width - 60, 50);
    btnSelectFile.backgroundColor = [UIColor colorWithRed:0.16 green:0.21 blue:0.31 alpha:1.0];
    btnSelectFile.layer.cornerRadius = 10;
    [btnSelectFile setTitle:@"📁 NẠP FILE HÀNH TRÌNH (GPX/GEOJSON)" forState:UIControlStateNormal];
    [btnSelectFile addTarget:self action:@selector(openFilePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnSelectFile];
    
    lblStatus = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, self.view.frame.size.width - 40, 30)];
    lblStatus.text = @"Trạng thái: Chưa có tệp dữ liệu";
    lblStatus.textColor = [UIColor lightGrayColor];
    lblStatus.textAlignment = NSTextAlignmentCenter;
    lblStatus.font = [UIFont systemFontOfSize:13];
    [self.view addSubview:lblStatus];
    
    lblSpeedText = [[UILabel alloc] initWithFrame:CGRectMake(30, 250, self.view.frame.size.width - 60, 20)];
    lblSpeedText.text = @"Tốc độ di chuyển: 5.0 km/h";
    lblSpeedText.textColor = [UIColor whiteColor];
    lblSpeedText.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:lblSpeedText];
    
    sliderSpeed = [[UISlider alloc] initWithFrame:CGRectMake(30, 280, self.view.frame.size.width - 60, 20)];
    sliderSpeed.minimumValue = 5.0;
    sliderSpeed.maximumValue = 20.0;
    sliderSpeed.value = 5.0;
    [sliderSpeed addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:sliderSpeed];
    
    btnPlayPause = [UIButton buttonWithType:UIButtonTypeCustom];
    btnPlayPause.frame = CGRectMake(30, 340, self.view.frame.size.width - 60, 55);
    btnPlayPause.backgroundColor = [UIColor grayColor];
    btnPlayPause.layer.cornerRadius = 12;
    [btnPlayPause setTitle:@"▶️ BẮT ĐẦU FAKE TOÀN MÁY" forState:UIControlStateNormal];
    btnPlayPause.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    btnPlayPause.enabled = NO;
    [btnPlayPause addTarget:self action:@selector(playPausePressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnPlayPause];
}

- (void)speedChanged:(UISlider *)sender {
    lblSpeedText.text = [NSString stringWithFormat:@"Tốc độ di chuyển: %.1f km/h", sender.value];
}

- (void)openFilePicker {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *types = @[UTTypeXML, UTTypeJSON, UTTypePlainText, UTTypeData];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        
        // 🚀 ĐÃ VÁ LỖI CHÍ MẠNG: Ủy thác quyền tiếp nhận tệp dữ liệu về cho hàm documentPicker xử lý bên dưới
        picker.delegate = self;
        
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:picker animated:YES completion:nil];
    });
}

// HÀM TIẾP NHẬN DỮ LIỆU FILE KHI ĐỨC NHẤP CHỌN TRÊN VIDEO
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    
    [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    [url stopAccessingSecurityScopedResource];
    
    if (content && !error) {
        [gpxPoints removeAllObjects];
        currentPointIndex = 0;
        
        // Quét tìm chuỗi tọa độ bằng biểu thức chính quy cải tiến
        NSRegularExpression *latRegex = [NSRegularExpression regularExpressionWithPattern:@"lat=['\"]([^'\"]+)['\"]" options:0 error:nil];
        NSRegularExpression *lonRegex = [NSRegularExpression regularExpressionWithPattern:@"lon=['\"]([^'\"]+)['\"]" options:0 error:nil];
        
        NSRegularExpression *pointBlockRegex = [NSRegularExpression regularExpressionWithPattern:@"<(trkpt|wpt|pnt)[^>]+>" options:0 error:nil];
        NSArray *blocks = [pointBlockRegex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
        
        for (NSTextCheckingResult *blockMatch in blocks) {
            NSString *blockStr = [content substringWithRange:blockMatch.range];
            NSTextCheckingResult *latMatch = [latRegex firstMatchInString:blockStr options:0 range:NSMakeRange(0, blockStr.length)];
            NSTextCheckingResult *lonMatch = [lonRegex firstMatchInString:blockStr options:0 range:NSMakeRange(0, blockStr.length)];
            
            if (latMatch && lonMatch) {
                double lat = [[blockStr substringWithRange:[latMatch rangeAtIndex:1]] doubleValue];
                double lon = [[blockStr substringWithRange:[lonMatch rangeAtIndex:1]] doubleValue];
                [gpxPoints addObject:@{@"lat": @(lat), @"lon": @(lon)}];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->gpxPoints.count > 0) {
                self->lblStatus.text = [NSString stringWithFormat:@"🟢 Đã nạp thành công %lu điểm tọa độ!", (unsigned long)self->gpxPoints.count];
                self->lblStatus.textColor = [UIColor systemGreenColor];
                self->btnPlayPause.backgroundColor = [UIColor systemGreenColor];
                self->btnPlayPause.enabled = YES;
                
                [self writeLocationToSystemLat:[self->gpxPoints[0][@"lat"] doubleValue] lon:[self->gpxPoints[0][@"lon"] doubleValue]];
            } else {
                self->lblStatus.text = @"🔴 Lỗi: File GPX không chứa tag tọa độ hợp lệ!";
                self->lblStatus.textColor = [UIColor systemRedColor];
            }
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->lblStatus.text = @"🔴 Thất bại: Lỗi hệ thống không đọc được file!";
            self->lblStatus.textColor = [UIColor systemRedColor];
        });
    }
}

- (void)writeLocationToSystemLat:(double)lat lon:(double)lon {
    NSDictionary *simulationPlist = @{
        @"SimulationType": @(1),
        @"SimulatedLatitude": @(lat),
        @"SimulatedLongitude": @(lon)
    };
    [simulationPlist writeToFile:systemCachePath atomically:YES];
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.apple.locationd.simulation"), NULL, NULL, YES);
    #pragma clang diagnostic pop
}

- (void)playPausePressed {
    if (isPlaying) {
        isPlaying = NO;
        [btnPlayPause setTitle:@"▶️ TIẾP TỤC FAKE TOÀN MÁY" forState:UIControlStateNormal];
        btnPlayPause.backgroundColor = [UIColor systemGreenColor];
    } else {
        isPlaying = YES;
        [btnPlayPause setTitle:@"⏸️ TẠM DỪNG FAKE" forState:UIControlStateNormal];
        btnPlayPause.backgroundColor = [UIColor systemOrangeColor];
        [self startSimulationLoop];
    }
}

- (void)startSimulationLoop {
    if (!isPlaying || gpxPoints.count == 0) return;
    
    dispatch_async(geoQueue, ^{
        if (self->currentPointIndex >= self->gpxPoints.count) self->currentPointIndex = 0;
        
        NSDictionary *point = self->gpxPoints[self->currentPointIndex];
        [self writeLocationToSystemLat:[point[@"lat"] doubleValue] lon:[point[@"lon"] doubleValue]];
        
        self->currentPointIndex++;
        
        __block double currentSpeed = 5.0;
        dispatch_sync(dispatch_get_main_queue(), ^{
            currentSpeed = self->sliderSpeed.value;
        });
        
        double interval = (3.6 / currentSpeed);
        if (interval < 1.0) interval = 1.0;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), self->geoQueue, ^{
            [self startSimulationLoop];
        });
    });
}
@end
