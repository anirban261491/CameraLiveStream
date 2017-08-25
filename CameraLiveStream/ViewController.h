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
@interface ViewController : UIViewController<AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncUdpSocketDelegate>
@property (weak, nonatomic) IBOutlet UIView *VideoView;


@end

