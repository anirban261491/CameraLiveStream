//
//  ViewController.m
//  CameraLiveStream
//
//  Created by Anirban on 8/23/17.
//  Copyright © 2017 Anirban. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()
{
    AVCaptureDeviceInput *cameraDeviceInput;
    AVCaptureSession* captureSession;
    
    
    VTCompressionSessionRef compressionSession;
    
}
@end

@implementation ViewController

bool timebaseSet=false;
bool encodeVideo=true;
AVSampleBufferDisplayLayer* displayLayer;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self initializeDisplayLayer];
    [self initializeVideoCaptureSession];
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
    // The video can either be encoded, decoded and then displayed... or just displayed with no encoding
    if(encodeVideo)
    {
        CFRetain(sampleBuffer);
        
        //NSLog(@"PTS: %f", CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)));
        
        CVPixelBufferRef pixelBuffer =CMSampleBufferGetImageBuffer(sampleBuffer);
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        
        VTEncodeInfoFlags flags;
        
        VTCompressionSessionEncodeFrame(compressionSession, pixelBuffer, pts, duration, NULL, NULL, &flags);
        
        CFRelease(sampleBuffer);
    }
    else
    {
        CFRetain(sampleBuffer);
        
        [displayLayer enqueueSampleBuffer:sampleBuffer];
        
        CFRelease(sampleBuffer);
    }
}


-(void) initializeCompressionSession
{
    OSStatus err = noErr;
    
    err = VTCompressionSessionCreate(kCFAllocatorDefault, self.VideoView.frame.size.width, self.VideoView.frame.size.height, kCMVideoCodecType_H264, NULL, NULL, NULL, &vtCallback, (__bridge void*) self, &compressionSession);
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    char one=1;
    CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, 1, &one);
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_MaxFrameDelayCount, n);
    if(err == noErr)
    {
        NSLog(@"Compression Session Create Success!");
    }
    else
    {
        NSLog(@"Compression Session Create Failed: %d", (int) err);
    }
}

void vtCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer )
{
    double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    
    if(!timebaseSet && pts != 0)
    {
        timebaseSet = true;
        
        CMTimebaseRef controlTimebase;
        CMTimebaseCreateWithMasterClock( CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
        
        displayLayer.controlTimebase = controlTimebase;
        CMTimebaseSetTime(displayLayer.controlTimebase, CMTimeMake(pts, 1));
        CMTimebaseSetRate(displayLayer.controlTimebase, 1.0);
    }
    
    
    if([displayLayer isReadyForMoreMediaData])
    {
        [displayLayer enqueueSampleBuffer:sampleBuffer];
    }
    else
    {
        NSLog(@"Not Ready...");
    }
}


-(void) startCaputureSession
{
    if(encodeVideo)
    {
        [self initializeCompressionSession];
    }
    
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
    if([captureSession isRunning])
    {
        [self stopCaputureSession];
    }
    else
    {
        [self startCaputureSession];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
