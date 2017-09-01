//
//  ViewController.h
//  CameraLiveStream
//
//  Created by Anirban on 8/23/17.
//  Copyright © 2017 Anirban. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "GCDAsyncUdpSocket.h"
#import "H264HwEncoderImpl.h"
@interface ViewController : UIViewController<AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncUdpSocketDelegate,H264HwEncoderImplDelegate>
@property (weak, nonatomic) IBOutlet UIView *VideoView;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) int spsSize;
@property (nonatomic, assign) int ppsSize;
-(void) receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize;
extern ViewController *v;
@end

