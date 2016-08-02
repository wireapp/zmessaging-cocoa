// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import ZMCSystem;
@import ZMTransport;

#import "ZMSingleRequestSync.h"
#import "ZMOperationLoop.h"

@interface ZMSingleRequestSync ()

@property (nonatomic, weak) id<ZMSingleRequestTranscoder> transcoder;
@property (nonatomic) ZMSingleRequestProgress status;
@property (nonatomic) ZMTransportRequest *currentRequest;
@property (nonatomic) int requestUniqueCounter;
@end


@implementation ZMSingleRequestSync

- (instancetype)initWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder managedObjectContext:(NSManagedObjectContext *)moc;

{
    self = [super init];
    if(self) {
        self.transcoder = transcoder;
        _moc = moc;
    }
    return self;
}

+ (instancetype)syncWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder managedObjectContext:(NSManagedObjectContext *)moc
{
    return [[self alloc] initWithSingleRequestTranscoder:transcoder managedObjectContext:moc];
}

- (NSString *)description
{
    id<ZMSingleRequestTranscoder> transcoder = self.transcoder;
    return [NSString stringWithFormat:@"<%@: %p> transcoder: <%@: %p>",
            self.class, self,
            transcoder.class, transcoder];
}

- (void)readyForNextRequest
{
    ++self.requestUniqueCounter;
    self.currentRequest = nil;
    self.status = ZMSingleRequestReady;
}

- (void)readyForNextRequestIfNotBusy
{
    if(self.currentRequest == nil) {
        [self readyForNextRequest];
    }
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMSingleRequestTranscoder> transcoder = self.transcoder;
    if(self.currentRequest == nil && self.status == ZMSingleRequestReady) {
        ZMTransportRequest *request = [transcoder requestForSingleRequestSync:self];
        [request setDebugInformationTranscoder:transcoder];

        self.currentRequest = request;
        if(request == nil) {
            self.status = ZMSingleRequestCompleted;
        } else {
            self.status = ZMSingleRequestInProgress;
        }
        const int currentCounter = self.requestUniqueCounter;
        ZM_WEAK(self);
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.moc block:^(ZMTransportResponse * response) {
            ZM_STRONG(self);
            [self processResponse:response forRequest:request counterValueAtStart:currentCounter];
        }]];
        return request;
    }
    return nil;
}

- (void)processResponse:(ZMTransportResponse *)response forRequest:(ZMTransportRequest * __unused)request counterValueAtStart:(int)counterValue
{
    const BOOL isRequestStillValid = counterValue == self.requestUniqueCounter;
    if(!isRequestStillValid) {
        return;
    };
    
    self.currentRequest = nil;
    
    switch (response.result) {
        case ZMTransportResponseStatusSuccess:
        case ZMTransportResponseStatusPermanentError:
        case ZMTransportResponseStatusExpired: // TODO Offline
        {
            self.status = ZMSingleRequestCompleted;
            [self.transcoder didReceiveResponse:response forSingleRequest:self];
            break;
        }
        case ZMTransportResponseStatusTryAgainLater: {
            [self readyForNextRequest];
            break;
        }
        case ZMTransportResponseStatusTemporaryError: {
            self.status = ZMSingleRequestReady;
            break;
        }
    }
}

- (void)resetCompletionState
{
    if(self.status == ZMSingleRequestCompleted) {
        self.status = ZMSingleRequestIdle;
    }
}

@end
