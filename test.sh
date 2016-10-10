#!/bin/sh

set -o pipefail
xcodebuild clean build test -scheme zmessaging-ios -destination 'platform=iOS Simulator,name=iPhone 7,OS=10.0' | xcpretty
