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


@import WireTransport;

#import "ZMEnvironmentsSetup.h"

static NSString * const ProductionBackendHost = @"prod-nginz-https.wire.com";
static NSString * const ProductionBackendWSHost = @"prod-nginz-ssl.wire.com";
static NSString * const ProductionFrontendHost = @"wire.com";

static NSString * const StagingBackendHost = @"staging-nginz-https.zinfra.io";
static NSString * const StagingBackendWSHost = @"staging-nginz-ssl.zinfra.io";
static NSString * const StagingFrontendHost = @"staging-website.zinfra.io";

static NSString * const ZMBlacklistEndPoint_IOS = @"clientblacklist.wire.com/prod/ios";
static NSString * const ZMBlacklistEndPoint_IOS_Staging = @"clientblacklist.wire.com/staging/ios";

static NSString *const CertificateNameProduction = @"com.wire";
static NSString *const CertificateNameAlpha = @"com.wire.ent";
static NSString *const CertificateNameDevelopment = @"com.wire.dev.ent";
static NSString *const CertificateNameInternal = @"com.wire.int.ent";

static NSString *const BundleIDProduction = @"com.wearezeta.zclient.ios";
static NSString *const BundleIDAlpha = @"com.wearezeta.zclient-alpha";
static NSString *const BundleIDDevelopment = @"com.wearezeta.zclient.ios-development";
static NSString *const BundleIDInternalBuild = @"com.wearezeta.zclient.ios-internal";



void zmSetupEnvironments(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [ZMBackendEnvironment setupEnvironmentOfType:ZMBackendEnvironmentTypeProduction
                                     withBackendHost:ProductionBackendHost
                                              wsHost:ProductionBackendWSHost
                                   blackListEndpoint:ZMBlacklistEndPoint_IOS
                                        frontendHost:ProductionFrontendHost];
        
        [ZMBackendEnvironment setupEnvironmentOfType:ZMBackendEnvironmentTypeStaging
                                     withBackendHost:StagingBackendHost
                                              wsHost:StagingBackendWSHost
                                   blackListEndpoint:ZMBlacklistEndPoint_IOS_Staging
                                        frontendHost:StagingFrontendHost];
        
        [ZMAPNSEnvironment setupForProductionWithCertificateName:CertificateNameProduction];
        
        [ZMAPNSEnvironment setupForEnterpriseWithBundleId:BundleIDAlpha
                                      withCertificateName:CertificateNameAlpha];
        
        [ZMAPNSEnvironment setupForEnterpriseWithBundleId:BundleIDDevelopment
                                      withCertificateName:CertificateNameDevelopment];
        
        [ZMAPNSEnvironment setupForEnterpriseWithBundleId:BundleIDInternalBuild
                                      withCertificateName:CertificateNameInternal];
    });
}
