#!/bin/sh

xcodebuild build test -scheme zmessaging-ios -destination 'platform=iOS Simulator,name=iPhone 6s,OS=9.3' | tee build.log | xcpretty -s 
