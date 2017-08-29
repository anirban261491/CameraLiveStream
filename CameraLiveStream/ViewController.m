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
ViewController *v=nil;
@implementation ViewController

GCDAsyncUdpSocket *udpSocket;
int tag;
bool timebaseSet=false;
bool encodeVideo=true;
AVSampleBufferDisplayLayer* displayLayer;

NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)", // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)", // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)", // SPS parameter
    @"8: Picture parameter set (non-VCL)", // PPS parameter
    @"9: Access unit delimiter (non-VCL)",
    @"10: End of sequence (non-VCL)",
    @"11: End of stream (non-VCL)",
    @"12: Filler data (non-VCL)",
    @"13: Sequence parameter set extension (non-VCL)",
    @"14: Prefix NAL unit (non-VCL)",
    @"15: Subset sequence parameter set (non-VCL)",
    @"16: Reserved (non-VCL)",
    @"17: Reserved (non-VCL)",
    @"18: Reserved (non-VCL)",
    @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    @"20: Coded slice extension (non-VCL)",
    @"21: Coded slice extension for depth view components (non-VCL)",
    @"22: Reserved (non-VCL)",
    @"23: Reserved (non-VCL)",
    @"24: STAP-A Single-time aggregation packet (non-VCL)",
    @"25: STAP-B Single-time aggregation packet (non-VCL)",
    @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
    @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
    @"28: FU-A Fragmentation unit (non-VCL)",
    @"29: FU-B Fragmentation unit (non-VCL)",
    @"30: Unspecified (non-VCL)",
    @"31: Unspecified (non-VCL)",
};


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    tag=0;
    dispatch_queue_t queue = dispatch_queue_create("com.livestream.queue", DISPATCH_QUEUE_SERIAL);
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:queue];
    [self initializeDisplayLayer];
    [self initializeVideoCaptureSession];
    v=self;
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
    
    
//    if([displayLayer isReadyForMoreMediaData])
//    {
//        [displayLayer enqueueSampleBuffer:sampleBuffer];
//    }
//    else
//    {
//        NSLog(@"Not Ready...");
//    }
    NSMutableData *elementaryStream = [NSMutableData data];
    BOOL isIFrame = NO;
    CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, 0);
    if (CFArrayGetCount(attachmentsArray)) {
        CFBooleanRef notSync;
        CFDictionaryRef dict = CFArrayGetValueAtIndex(attachmentsArray, 0);
        BOOL keyExists = CFDictionaryGetValueIfPresent(dict,
                                                       kCMSampleAttachmentKey_NotSync,
                                                       (const void **)&notSync);
        // An I-Frame is a sync frame
        isIFrame = !keyExists || !CFBooleanGetValue(notSync);
    }
    
    static const size_t startCodeLength = 4;
    static const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
    if (isIFrame) {
        CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        // Find out how many parameter sets there are
        size_t numberOfParameterSets;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           0, NULL, NULL,
                                                           &numberOfParameterSets,
                                                           NULL);
        
        // Write each parameter set to the elementary stream
        for (int i = 0; i < numberOfParameterSets; i++) {
            const uint8_t *parameterSetPointer;
            size_t parameterSetLength;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                               i,
                                                               &parameterSetPointer,
                                                               &parameterSetLength,
                                                               NULL, NULL);
            
            // Write the parameter set to the elementary stream
            [elementaryStream appendBytes:startCode length:startCodeLength];
            [elementaryStream appendBytes:parameterSetPointer length:parameterSetLength];
        }
    }
    
    size_t blockBufferLength;
    uint8_t *bufferDataPointer = NULL;
    CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sampleBuffer),
                                0,
                                NULL,
                                &blockBufferLength,
                                (char **)&bufferDataPointer);
    
    // Loop through all the NAL units in the block buffer
    // and write them to the elementary stream with
    // start codes instead of AVCC length headers
    size_t bufferOffset = 0;
    static const int AVCCHeaderLength = 4;
    
    while (bufferOffset < blockBufferLength - AVCCHeaderLength) {
        // Read the NAL unit length
        uint32_t NALUnitLength = 0; memcpy(&NALUnitLength, bufferDataPointer + bufferOffset, AVCCHeaderLength);
        // Convert the length value from Big-endian to Little-endian
        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
        // Write start code to the elementary stream
        [elementaryStream appendBytes:startCode length:startCodeLength];
        // Write the NAL unit without the AVCC length header to the elementary stream
        [elementaryStream appendBytes:bufferDataPointer + bufferOffset + AVCCHeaderLength length:NALUnitLength];
        // Move to the next NAL unit in the block buffer
        bufferOffset += AVCCHeaderLength + NALUnitLength;
    }
    
    uint8_t *bytes = (uint8_t*)[elementaryStream bytes];
    int size = (int)[elementaryStream length];
    //NSUInteger len = [elementaryStream length];
    //Byte *bytes = (Byte*)malloc(size);
    //memcpy(bytes, [elementaryStream bytes], size);
    
    
    
    [v receivedRawVideoFrame:bytes withSize:size];
    
    //NSData *data=[NSData dataWithBytes:bytes length:size];
    
   // [udpSocket sendData:data toHost:@"172.20.10.4" port:1900 withTimeout:-1 tag:tag];
   // tag++;
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


-(void)startServer
{
    NSError *error;
    if (![udpSocket bindToPort:1900 error:&error])
    {
        NSLog(@"Bind error");
    }
    if (![udpSocket beginReceiving:&error])
    {
        [udpSocket close];
        
        NSLog(@"Receiving error");
        return;
    }
}

-(void) receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    OSStatus status;
    
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    
    // I know how my H.264 data source's NALUs looks like so I know start code index is always 0.
    // if you don't know where it starts, you can use a for loop similar to how I find the 2nd and 3rd start codes
    
    int startCodeIndex = 0;
    int secondStartCodeIndex = 0;
    int thirdStartCodeIndex = 0;
    
    long blockLength = 0;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    int nalu_type = (frame[startCodeIndex + 4] & 0x1F);
    NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    
    // if we havent already set up our format description with our SPS PPS parameters, we
    // can't process any frames except type 7 that has our parameters
    if (nalu_type != 7 && _formatDesc == NULL)
    {
        NSLog(@"Video error: Frame is not an I Frame and format description is null");
        return;
    }
    
    // NALU type 7 is the SPS parameter NALU
    if (nalu_type == 7)
    {
        // find where the second PPS start code begins, (the 0x00 00 00 01 code)
        // from which we also get the length of the first SPS code
        for (int i = startCodeIndex + 4; i < startCodeIndex + 40; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                secondStartCodeIndex = i;
                _spsSize = secondStartCodeIndex;   // includes the header in the size
                break;
            }
        }
        
        // find what the second NALU type is
        nalu_type = (frame[secondStartCodeIndex + 4] & 0x1F);
        NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    }
    
    
    // type 8 is the PPS parameter NALU
    if(nalu_type == 8) {
        
        // find where the NALU after this one starts so we know how long the PPS parameter is
        for (int i = _spsSize + 12; i < _spsSize + 50; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                thirdStartCodeIndex = i;
                _ppsSize = thirdStartCodeIndex - _spsSize;
                break;
            }
        }
        
        // allocate enough data to fit the SPS and PPS parameters into our data objects.
        // VTD doesn't want you to include the start code header (4 bytes long) so we add the - 4 here
        sps = malloc(_spsSize - 4);
        pps = malloc(_ppsSize - 4);
        
        // copy in the actual sps and pps values, again ignoring the 4 byte header
        memcpy (sps, &frame[4], _spsSize-4);
        memcpy (pps, &frame[_spsSize+4], _ppsSize-4);
        
        // now we set our H264 parameters
        uint8_t*  parameterSetPointers[2] = {sps, pps};
        size_t parameterSetSizes[2] = {_spsSize-4, _ppsSize-4};
        
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                     (const uint8_t *const*)parameterSetPointers,
                                                                     parameterSetSizes, 4,
                                                                     &_formatDesc);
        
        NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
        if(status != noErr) NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
        
        // See if decomp session can convert from previous format description
        // to the new one, if not we need to remake the decomp session.
        // This snippet was not necessary for my applications but it could be for yours
        /*BOOL needNewDecompSession = (VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, _formatDesc) == NO);
         if(needNewDecompSession)
         {
         [self createDecompSession];
         }*/
        
        // now lets handle the IDR frame that (should) come after the parameter sets
        // I say "should" because that's how I expect my H264 stream to work, YMMV
        nalu_type = (frame[thirdStartCodeIndex + 4] & 0x1F);
        NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    }
    
    // create our VTDecompressionSession.  This isnt neccessary if you choose to use AVSampleBufferDisplayLayer
    if((status == noErr) && (_decompressionSession == NULL))
    {
        [self createDecompSession];
    }
    
    // type 5 is an IDR frame NALU.  The SPS and PPS NALUs should always be followed by an IDR (or IFrame) NALU, as far as I know
    if(nalu_type == 5)
    {
        // find the offset, or where the SPS and PPS NALUs end and the IDR frame NALU begins
        int offset = _spsSize + _ppsSize;
        blockLength = frameSize - offset;
        //        NSLog(@"Block Length : %ld", blockLength);
        data = malloc(blockLength);
        data = memcpy(data, &frame[offset], blockLength);
        
        // replace the start code header on this NALU with its size.
        // AVCC format requires that you do this.
        // htonl converts the unsigned int from host to network byte order
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        // create a block buffer from the IDR NALU
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold buffered data
                                                    blockLength,  // block length of the mem block in bytes.
                                                    kCFAllocatorNull, NULL,
                                                    0, // offsetToData
                                                    blockLength,   // dataLength of relevant bytes, starting at offsetToData
                                                    0, &blockBuffer);
        
        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    // NALU type 1 is non-IDR (or PFrame) picture
    if (nalu_type == 1)
    {
        // non-IDR frames do not have an offset due to SPS and PSS, so the approach
        // is similar to the IDR frames just without the offset
        blockLength = frameSize;
        data = malloc(blockLength);
        data = memcpy(data, &frame[0], blockLength);
        
        // again, replace the start header with the size of the NALU
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold data. If NULL, block will be alloc when needed
                                                    blockLength,  // overall length of the mem block in bytes
                                                    kCFAllocatorNull, NULL,
                                                    0,     // offsetToData
                                                    blockLength,  // dataLength of relevant data bytes, starting at offsetToData
                                                    0, &blockBuffer);
        
        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    // now create our sample buffer from the block buffer,
    if(status == noErr)
    {
        // here I'm not bothering with any timing specifics since in my case we displayed all frames immediately
        const size_t sampleSize = blockLength;
        status = CMSampleBufferCreate(kCFAllocatorDefault,
                                      blockBuffer, true, NULL, NULL,
                                      _formatDesc, 1, 0, NULL, 1,
                                      &sampleSize, &sampleBuffer);
        
        NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
    }
    
    if(status == noErr)
    {
        // set some values of the sample buffer's attachments
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        
        // either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
        [self render:sampleBuffer];
    }
    
    // free memory to avoid a memory leak, do the same for sps, pps and blockbuffer
    if (NULL != data)
    {
        free (data);
        data = NULL;
    }
}

-(void) createDecompSession
{
    // make sure to destroy the old VTD session
    _decompressionSession = NULL;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    
    // this is necessary if you need to make calls to Objective C "self" from within in the callback method.
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    // you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
    // if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
    /*NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
     [NSNumber numberWithBool:YES],
     (id)kCVPixelBufferOpenGLESCompatibilityKey,
     nil];*/
    
    OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc, NULL,
                                                    NULL, // (__bridge CFDictionaryRef)(destinationImageBufferAttributes)
                                                    &callBackRecord, &_decompressionSession);
    NSLog(@"Video Decompression Session Create: \t %@", (status == noErr) ? @"successful!" : @"failed...");
    if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
}

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration)
{
    
    if (status != noErr)
    {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"Decompressed error: %@", error);
    }
    else
    {
        NSLog(@"Decompressed sucessfully");
    }
}

- (void) render:(CMSampleBufferRef)sampleBuffer
{
    /*
     VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
     VTDecodeInfoFlags flagOut;
     NSDate* currentTime = [NSDate date];
     VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,
     (void*)CFBridgingRetain(currentTime), &flagOut);
     
     CFRelease(sampleBuffer);*/
    
    // if you're using AVSampleBufferDisplayLayer, you only need to use this line of code
    if (displayLayer) {
        NSLog(@"Success ****");
        [displayLayer enqueueSampleBuffer:sampleBuffer];
    }
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
