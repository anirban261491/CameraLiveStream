//
//  ViewController.h
//  CameraLiveStream
//
//  Created by Anirban on 8/23/17.
//  Copyright © 2017 Anirban. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "GCDAsyncUdpSocket.h"
#import "H264HwEncoderImpl.h"
@interface ViewController : UIViewController<AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncUdpSocketDelegate,H264HwEncoderImplDelegate>
@property (weak, nonatomic) IBOutlet UIView *VideoView;
@property (weak, nonatomic) IBOutlet WKWebView *WebView;

@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) int spsSize;
@property (weak, nonatomic) IBOutlet UIView *videoContainerView;
@property (nonatomic, assign) int ppsSize;
@end

