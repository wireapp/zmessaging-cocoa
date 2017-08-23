# Wire™

[![Wire logo](https://github.com/wireapp/wire/blob/master/assets/header-small.png?raw=true)](https://wire.com/jobs/)


[![CircleCI](https://circleci.com/gh/wireapp/wire-ios-sync-engine.svg?style=shield)](https://circleci.com/gh/wireapp/wire-ios-sync-engine) [![codecov](https://codecov.io/gh/wireapp/wire-ios-sync-engine/branch/develop/graph/badge.svg)](https://codecov.io/gh/wireapp/wire-ios-sync-engine)

This repository is part of the source code of Wire. You can find more information at [wire.com](https://wire.com) or by contacting opensource@wire.com.

You can find the published source code at [github.com/wireapp/wire](https://github.com/wireapp/wire).

#Wire iOS Sync Engine

The wire-ios-sync-engine framework is used as part of the [Wire iOS client](http://github.com/wireapp/wire-ios) and is the top-most layer of the underlying *sync engine*. It is using a number of lower-level frameworks. *wire-ios-sync-engine* and the lower-lever frameworks constitute the iOS *sync engine*, as illustrated in the following picture.

![iOS architecture](https://github.com/wireapp/wire/blob/master/assets/ios-se-architecture.png?raw=true)

The Wire iOS sync engine is developed in a mix of Objective-C and Swift (and just a handful of classes in Objective-C++). It is a result of a long development process that was started in Objective-C when Swift was not yet available. In the past year, parts of it have been written or rewritten in Swift. Going forward, expect new functionalities to be developed almost exclusively in Swift.

## How to build

*iOS SyncEngine* is build with Xcode 8 using Swift 3.

It is using [Carthage](https://github.com/Carthage/Carthage) to manage dependencies. To pull the dependencies binaries run `carthage bootstrap —-platform ios`.

You can now open the Xcode project and build.

## Repositories

- [wire-ios-utilities](https://github.com/wireapp/wire-ios-utilities): implements common data structures, algorithms (such as symmetric encryption) and application environment detection (internal or public build / production or staging backend)
- [wire-ios-system](https://github.com/wireapp/wire-ios-system): covers interaction with ASL (Apple System Log), profiling and wrappers of some foundation/cocoa classes
- [wire-ios-transport](https://github.com/wireapp/wire-ios-transport): abstracts the network communication with the backend: handles authentication of requests, network failures and retries transparently
- [wire-ios-testing](https://github.com/wireapp/wire-ios-testing): testing utilities
- [wire-ios-protos](https://github.com/wireapp/wire-ios-protos): precompiled protocol buffer definitions for objective-c / swift and some convenience methods around them
- [wire-ios-mocktransport](https://github.com/wireapp/wire-ios-mocktransport): simulates the entire network component (including backend behaviour) for testing purposes
- [wire-ios-images](https://github.com/wireapp/wire-ios-images): performs rotation and scaling of images
- [wire-ios-cryptobox](https://github.com/wireapp/wire-ios-cryptobox): higher level convenience wrappers around cryptobox for iOS
- [wire-ios-data-model](https://github.com/wireapp/wire-ios-data-model): Core Data model and entity classes
- [cryptobox-ios](https://github.com/wireapp/cryptobox-ios): iOS binaries for cryptobox
- [wire-ios-link-preview](http://github.com/wireapp/wire-ios-link-preview): OpenGraph processor (fetching and parsing)
- [wire-ios-message-strategy](http://github.com/wireapp/wire-ios-message-strategy): generates network requests needed to exchange data with the backend (send messages, get list of contacts, etc.)
- [wire-ios-request-strategy](http://github.com/wireapp/wire-ios-request-strategy): abstraction of network request generators

