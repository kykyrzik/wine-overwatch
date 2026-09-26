#import <AVFoundation/AVFoundation.h>
#include <stdio.h>

int main(int argc, const char **argv)
{
    @autoreleasepool {
        FILE *out = fopen(argc > 1 ? argv[1] : "/dev/stderr", "a");
        AVAuthorizationStatus before = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
        fprintf(out, "pid=%d ppid=%d status_before=%ld\n", getpid(), getppid(), (long)before);
        fflush(out);
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block BOOL granted = NO;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL ok) {
            granted = ok;
            dispatch_semaphore_signal(done);
        }];
        long timed_out = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC));
        fprintf(out, "timed_out=%ld granted=%d status_after=%ld\n", timed_out, granted,
                (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]);
        fclose(out);
    }
    return 0;
}
