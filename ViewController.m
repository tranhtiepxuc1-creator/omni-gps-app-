#import "ViewController.h"
#import <CoreLocation/CoreLocation.h>

@interface ViewController () {
    UIButton *btnSelectFile;
    UIButton *btnPlayPause;
    UILabel *lblStatus;
    UISlider *sliderSpeed;
    UILabel *lblSpeedText;
    
    NSMutableArray *gpxPoints;
    NSInteger currentPointIndex;
    BOOL isPlaying;
    dispatch_queue_t geoQueue;
    
    NSString *systemCachePath; // Đường dẫn file cache định vị hệ thống iOS
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLayoutSubviews];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:1.0];
    
    gpxPoints = [[NSMutableArray alloc] init];
    geoQueue = dispatch_queue_create("com.omni.app.queue", DISPATCH_QUEUE_SERIAL);
    
    // Khai báo đường dẫn lưu tọa độ ảo đè thẳng vào file hệ thống của TrollStore
    systemCachePath = @"/var/mobile/Library/Caches/com.apple.locationd/Simulation.plist";

    // --- TẠO GIAO DIỆN APP ĐỘC LẬP ---
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
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData, UTTypeText] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    
    NSString *content = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (content) {
        [gpxPoints removeAllObjects];
        currentPointIndex = 0;
        
        // Trích xuất tọa độ Lat/Lon chuẩn WGS-84 từ file GPX tĩnh
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"lat=\"([^\"]+)\" lon=\"([^\"]+)\"" options:0 error:nil];
        NSArray *matches = [regex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
        
        for (NSTextCheckingResult *match in matches) {
            double lat = [[content substringWithRange:[match rangeAtIndex:1]] doubleValue];
            double lon = [[content substringWithRange:[match rangeAtIndex:2]] doubleValue];
            [gpxPoints addObject:@{@"lat": @(lat), @"lon": @(lon)}];
        }
        
        if (gpxPoints.count > 0) {
            lblStatus.text = [NSString stringWithFormat:@"📁 Đã nạp thành công %lu điểm!", (unsigned long)gpxPoints.count];
            lblStatus.textColor = [UIColor systemGreenColor];
            btnPlayPause.backgroundColor = [UIColor systemGreenColor];
            btnPlayPause.enabled = YES;
            
            // ÉP TỌA ĐỘ ĐIỂM ĐẦU TOÀN MÁY NGAY KHI NẠP FILE
            [self writeLocationToSystemLat:[gpxPoints[0][@"lat"] doubleValue] lon:[gpxPoints[0][@"lon"] doubleValue]];
        }
    }
}

// 🌐 SỨC MẠNH TROLLSTORE: Ghi trực tiếp tọa độ giả lập đè lên file cấu hình dịch vụ locationd của hệ thống iOS
- (void)writeLocationToSystemLat:(double)lat lon:(double)lon {
    NSDictionary *simulationPlist = @{
        @"SimulationType": @(1),
        @"SimulatedLatitude": @(lat),
        @"SimulatedLongitude": @(lon)
    };
    // Ép ghi file hệ thống không cần qua Sandbox nhờ quyền đặc biệt của TrollStore
    [simulationPlist writeToFile:systemCachePath atomically:YES];
    
    // Ra lệnh thông báo cho dịch vụ hệ thống cập nhật tọa độ ảo tức thì
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

// VÒNG LẶP ĐIỀU KHIỂN THỜI GIAN CHẠY NGẦM ĐỂ TẠO DI CHUYỂN ĐỘNG TRÊN TOÀN CHIẾC IPHONE
- (void)startSimulationLoop {
    if (!isPlaying || gpxPoints.count == 0) return;
    
    dispatch_async(geoQueue, ^{
        if (currentPointIndex >= gpxPoints.count) currentPointIndex = 0;
        
        NSDictionary *point = gpxPoints[currentPointIndex];
        [self writeLocationToSystemLat:[point[@"lat"] doubleValue] lon:[point[@"lon"] doubleValue]];
        
        currentPointIndex++;
        
        // Tính toán khoảng thời gian delay dựa theo thanh gạt km/h
        double interval = (3.6 / sliderSpeed.value);
        if (interval < 1.0) interval = 1.0;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), geoQueue, ^{
            [self startSimulationLoop];
        });
    });
}
@end
