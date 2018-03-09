//
//  H264HwEncoderImpl.m
//  h264v1
//
//  Created by Ganvir, Manish on 3/31/15.
//  Copyright (c) 2015 Ganvir, Manish. All rights reserved.
//

#import "H264HwEncoderImpl.h"
#define YUV_FRAME_SIZE 2000
#define FRAME_WIDTH
#define NUMBEROFRAMES 300
#define DURATION 12

@import VideoToolbox;
@import AVFoundation;

@implementation H264HwEncoderImpl
{
    NSString * yuvFile;
    VTCompressionSessionRef EncodingSession;
    dispatch_queue_t aQueue;
    CMFormatDescriptionRef  format;
    CMSampleTimingInfo * timingInfo;
    BOOL initialized;
    int  frameCount;
    NSData *sps;
    NSData *pps;
}
@synthesize error;

- (void) initWithConfiguration
{
//    NSFileManager *fileManager = [NSFileManager defaultManager];
//    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    /*yuvFile = [documentsDirectory stringByAppendingPathComponent:@"test.i420"];
    
    if ([fileManager fileExistsAtPath:yuvFile] == NO) {
        NSLog(@"H264: File does not exist");
        return;
    }*/
    
    EncodingSession = nil;
    initialized = true;
    aQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    //aQueue = dispatch_queue_create("com.aQueue.Queue", DISPATCH_QUEUE_SERIAL);
    frameCount = 0;
    sps = NULL;
    pps = NULL;
    
}

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
CMSampleBufferRef sampleBuffer )
{
    //NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) return;
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
   H264HwEncoderImpl* encoder = (__bridge H264HwEncoderImpl*)outputCallbackRefCon;
   
   // Check if we have got a key frame first
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
   if (keyframe)
   {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
       // CFDictionaryRef extensionDict = CMFormatDescriptionGetExtensions(format);
       // Get the extensions
       // From the extensions get the dictionary with key "SampleDescriptionExtensionAtoms"
       // From the dict, get the value for the key "avcC"
       
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                // Found pps
                encoder->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                encoder->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder->_delegate)
                {
                    [encoder->_delegate gotSpsPps:encoder->sps pps:encoder->pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder->_delegate gotEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
        
    }
    
}


- (void) initEncode:(int)width  height:(int)height
{
    dispatch_sync(aQueue, ^{
        
        // For testing out the logic, lets read from a file and then send it to encoder to create h264 stream
        
        // Create the compression session
//        CFStringRef key = kVTVideoEncoderSpecification_EncoderID;
//        CFStringRef value = CFSTR("com.apple.videotoolbox.videoencoder.h264.gva");
//
//        CFStringRef bkey = CFSTR("EnableHardwareAcceleratedVideoEncoder");
//        CFBooleanRef bvalue = kCFBooleanTrue;
//
//        CFStringRef ckey = CFSTR("RequireHardwareAcceleratedVideoEncoder");
//        CFBooleanRef cvalue = kCFBooleanTrue;
//
//        CFMutableDictionaryRef encoderSpecifications = CFDictionaryCreateMutable(
//                                                          kCFAllocatorDefault,
//                                                          3,
//                                                          &kCFTypeDictionaryKeyCallBacks,
//                                                          &kCFTypeDictionaryValueCallBacks);
//
//        CFDictionaryAddValue(encoderSpecifications, bkey, bvalue);
//        CFDictionaryAddValue(encoderSpecifications, ckey, cvalue);
//        CFDictionaryAddValue(encoderSpecifications, key, value);
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self),  &EncodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            error = @"H264: Unable to create a H264 session";
            
            return ;
            
        }
        
        // Set the properties
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanFalse);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_5_2);
        int bitRate = 1000*1024;
        int bitRateLimit = (bitRate) / 8;
        
        // that's why we set data in byte/second
        CFNumberRef byteNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        int second = 1;
        CFNumberRef secNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &second);
        
        // add parameters into a array
        const void* numbers[2] = {byteNum, secNum};
        CFArrayRef dataRateLimits = CFArrayCreate(NULL, numbers, 2, &kCFTypeArrayCallBacks);
        //VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bitRate));
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_DataRateLimits, dataRateLimits);
        
        int frameRate=30;
        second=10;
        secNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &second);
        CFNumberRef frameRateValue = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &frameRate);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, frameRateValue);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, secNum);
        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(EncodingSession);
    });
}
- (void) encode:(CMSampleBufferRef )sampleBuffer
{
     dispatch_sync(aQueue, ^{
        
          frameCount++;
            // Get the CV Image buffer
            CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);

            // Create properties
            CMTime presentationTimeStamp = CMTimeMake(frameCount,30);
            //CMTime duration = CMTimeMake(1, DURATION);
            VTEncodeInfoFlags flags;
            
            // Pass it to the encoder
            OSStatus statusCode = VTCompressionSessionEncodeFrame(EncodingSession,
                                                         imageBuffer,
                                                         presentationTimeStamp,
                                                         kCMTimeInvalid,
                                                         NULL, NULL, &flags);
            // Check for error
            if (statusCode != noErr) {
                NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
                error = @"H264: VTCompressionSessionEncodeFrame failed ";
                
                // End the session
                VTCompressionSessionInvalidate(EncodingSession);
                CFRelease(EncodingSession);
                EncodingSession = NULL;
                error = NULL;
                return;
            }
            //NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
      });
    
    
}


- (void) End
{
    // Mark the completion
    VTCompressionSessionCompleteFrames(EncodingSession, kCMTimeInvalid);
    
    // End the session
    VTCompressionSessionInvalidate(EncodingSession);
    CFRelease(EncodingSession);
    EncodingSession = NULL;
    error = NULL;

}

@end
