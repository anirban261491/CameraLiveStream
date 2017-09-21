//
//  ViewController.m
//  CameraLiveStream
//
//  Created by Anirban on 8/23/17.
//  Copyright © 2017 Anirban. All rights reserved.
//

#import "ViewController.h"
#import <ReplayKit/ReplayKit.h>
@interface ViewController ()
{
    AVCaptureDeviceInput *cameraDeviceInput;
    AVCaptureSession* captureSession;
    H264HwEncoderImpl *h264Encoder;
    dispatch_queue_t backgroundQueue,sendScreenFramesForUploadQueue;
    NSInteger SCREENWIDTH,SCREENHEIGHT;
    RPScreenRecorder *recorder;
    NSMutableArray *frames;
}
@end

@implementation ViewController

GCDAsyncUdpSocket *udpSocket;
int tag,count;
bool timebaseSet=false;
bool encodeVideo=true;
AVSampleBufferDisplayLayer* displayLayer;



- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    frames=[NSMutableArray new];
    SCREENWIDTH=[UIScreen mainScreen].bounds.size.width;
    SCREENHEIGHT=[UIScreen mainScreen].bounds.size.height;
    tag=0;
    count=0;
    dispatch_queue_t queue = dispatch_queue_create("com.socketDelegate.queue", DISPATCH_QUEUE_SERIAL);
    backgroundQueue=dispatch_queue_create("com.livestream.backgroundQueue", DISPATCH_QUEUE_SERIAL);
    sendScreenFramesForUploadQueue=dispatch_queue_create("com.sendScreenFramesForUpload.Queue", DISPATCH_QUEUE_SERIAL);
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:queue];
    NSError *error;
    //[udpSocket enableBroadcast:YES error:&error];
    //[udpSocket setMaxSendBufferSize:1024];
    //[self initializeDisplayLayer];
    h264Encoder = [H264HwEncoderImpl alloc];
    [h264Encoder initWithConfiguration];
    //[self initializeVideoCaptureSession];
    [h264Encoder initEncode:750 height:1334];
    h264Encoder.delegate = self;
    [self initializeScreenRecorder];
    [self loadWebView];
    
}


-(void)loadWebView
{
    [_WebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.google.com"]]];
}

-(void)initializeScreenRecorder
{
    recorder=[RPScreenRecorder sharedRecorder];
}

-(void) initializeDisplayLayer
{
    //Initialize display layer
    displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    //Add the layer to the VideoView
    displayLayer.bounds = _VideoView.bounds;
    displayLayer.frame = _VideoView.frame;
    displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    displayLayer.position = CGPointMake(CGRectGetMidX(_VideoView.bounds), CGRectGetMidY(_VideoView.bounds));
    displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    // Remove from previous view if exists
    [displayLayer removeFromSuperlayer];
    
    [_VideoView.layer addSublayer:displayLayer];
}

-(void) initializeVideoCaptureSession
{
    // Create our capture session...
    captureSession = [AVCaptureSession new];
    
    // Get our camera device...
    //AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *cameraDevice = [self frontFacingCameraIfAvailable];
    
    NSError *error;
    
    // Initialize our camera device input...
    cameraDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:cameraDevice error:&error];
    
    // Finally, add our camera device input to our capture session.
    if ([captureSession canAddInput:cameraDeviceInput])
    {
        [captureSession addInput:cameraDeviceInput];
    }
    
    // Initialize image output
    AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];
    
    [output setAlwaysDiscardsLateVideoFrames:YES];
    
    dispatch_queue_t videoDataOutputQueue = dispatch_queue_create("video_data_output_queue", DISPATCH_QUEUE_SERIAL);
    
    [output setSampleBufferDelegate:self queue:videoDataOutputQueue];
    [output setVideoSettings:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil]];
    
    
    if( [captureSession canAddOutput:output])
    {
        [captureSession addOutput:output];
    }
    
    [[output connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    [h264Encoder initEncode:750 height:1334];
    h264Encoder.delegate = self;
}


-(AVCaptureDevice *)frontFacingCameraIfAvailable
{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == AVCaptureDevicePositionFront)
        {
            captureDevice = device;
            break;
        }
    }
    
    //  couldn't find one on the front, so just get the default video device.
    if (!captureDevice)
    {
        captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    return captureDevice;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if ([connection isVideoOrientationSupported]) {
        [connection setVideoOrientation:[UIDevice currentDevice].orientation];
    }
    
    [h264Encoder encode:sampleBuffer];
}


- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    
    
    dispatch_async(backgroundQueue, ^{
        [self formAndSendNALUnits:sps];
        [self formAndSendNALUnits:pps];
    });
    
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    NSLog(@"gotEncodedData %d", (int)[data length]);
    //static int framecount = 1;
    
    
    dispatch_async(backgroundQueue, ^{
        [self formAndSendNALUnits:data];
    });
    
}

-(void)formAndSendNALUnits:(NSData*)data
{
    const char startCode[] = "\x00\x00\x00\x01";
    size_t length = (sizeof startCode) - 1;
    int type = [self getNALUType:data];
    NSMutableData *NALUnit=[NSMutableData dataWithBytes:startCode length:length];
    [NALUnit appendData:data];
    [udpSocket sendData:NALUnit toHost:@"172.20.10.11" port:1900 withTimeout:-1 tag:tag++];
    NSLog(@"Packet - %d, Size - %lu, Type - %d",count++,[NALUnit length],type);
}


- (int)getNALUType:(NSData *)NALU {
    uint8_t * bytes = (uint8_t *) NALU.bytes;
    
    return bytes[0] & 0x1F;
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    NSLog(@"1");
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    NSLog(@"1");
}


-(void) startCaputureSession
{
    [captureSession startRunning];
    
    // You must call flush when resuming!
    if(displayLayer)
    {
        [displayLayer flushAndRemoveImage];
    }
    
    NSLog(@"Start Video Capture Session....");
}

-(void) stopCaputureSession
{
    [captureSession stopRunning];
    [displayLayer flushAndRemoveImage];
    
    NSLog(@"Stop Video Capture Session....");
}
- (IBAction)startPressed:(id)sender {
    //    if([captureSession isRunning])
    //    {
    //        [self stopCaputureSession];
    //    }
    //    else
    //    {
    //        [self startCaputureSession];
    //    }
    
    
        [recorder startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {
            if(bufferType==1)
                [h264Encoder encode:sampleBuffer];
        } completionHandler:^(NSError * _Nullable error) {
            NSLog(@"1");
        }];

}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
