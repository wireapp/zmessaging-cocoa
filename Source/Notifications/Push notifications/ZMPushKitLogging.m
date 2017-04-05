#import <asl.h>
#import "ZMPushRegistrant.h"
#import <dispatch/dispatch.h>




void ZMLogPushKit_s(NSString *text)
{
    ZMLogPushKit(@"%@", text);
}

BOOL ZMLogPushKit_enabled()
{
    static dispatch_once_t onceToken;
    static BOOL enabled;
    dispatch_once(&onceToken, ^{
        enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ZMPuskKitLoggingEnabled"];
    });
    return enabled;
}

void ZMLogPushKit(NSString *format, ...)
{
    if (! ZMLogPushKit_enabled()) {
        return;
    }
    
    static dispatch_once_t onceToken;
    static dispatch_queue_t isolation;
    static asl_object_t client;
    dispatch_once(&onceToken, ^{
        isolation = dispatch_queue_create("ZMLogPushKit", 0);
        
        // Add log file:
        client = asl_open(NULL, "ZMPushKit", ASL_OPT_STDERR);
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *logURL = [fm URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
        logURL = [logURL URLByAppendingPathComponent:@"Logs"];
        [fm createDirectoryAtURL:logURL withIntermediateDirectories:YES attributes:nil error:nil];
        logURL = [logURL URLByAppendingPathComponent:@"WireSyncEngine-PushKit.log"];
        // Open and add:
        mode_t const mode = S_IRUSR | S_IWUSR | S_IRGRP;
        int const fd = open(logURL.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, mode);
        if (0 <= fd) {
            int addResult = asl_add_log_file(client, fd);
            if (addResult != 0) {
                NSLog(@"Failed to add log file (%d).", addResult);
            }
        }
    });
    
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // N.B.: We want this to log synchronously. That's ok, since this isn't re-entrant.
    dispatch_sync(isolation, ^{
        asl_object_t message = asl_new(ASL_TYPE_MSG);
        asl_set(message, ASL_KEY_LEVEL, ASL_STRING_ERR);
        if (text != nil) {
            char buffer[400];
            if (0 < snprintf(buffer, sizeof(buffer), "[PushKit] %s", text.UTF8String)) {
                asl_set(message, ASL_KEY_MSG, buffer);
            }
        } else {
            asl_set(message, ASL_KEY_MSG, "[PushKit] ");
        }
        asl_send(client, message);
        asl_free(message);
    });
}
