//
//  Conversation_RoleTests_Quick_Nimble.swift
//  WireSyncEngine-iOS-Tests
//
//  Created by David Henner on 25.11.20.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Quick
import Nimble

class ExampleClassToTest {
    var didSomething: Bool = false
    var didSomethingElse: Bool = false
    
    func doSomething(with user: String?) {
        if let user = user {
            didSomething = true
            didSomethingElse = true
        }
    }
}

class QuickExampleTest: QuickSpec {
    override func spec() {
        var sut: ExampleClassToTest!
        
        beforeSuite {
            sut = ExampleClassToTest()
        }
        
        afterSuite {
            sut = nil
        }
        
        describe(".doSomething") {
            var user: String?
            
            beforeEach {
                sut.didSomething = false
                sut.didSomethingElse = false
            }
            
            context("when we have a user") {
                beforeEach {
                    user = "User"
                    sut.doSomething(with: user)
                }
                
                afterEach {
                    user = nil
                }
                
                it("does something and something else") {
                    expect(sut.didSomething).to(beTrue())
                    expect(sut.didSomethingElse).to(beTrue())
                }
                
                it("does something") {
                    expect(sut.didSomething).to(beTrue())
                }
                
                it("does something else") {
                    expect(sut.didSomethingElse).to(beTrue())
                }
            }
            
            context("when we don't have a user") {
                it("does nothing") {
                    sut.doSomething(with: user)
                    
                    expect(sut.didSomething).to(beFalse())
                }
            }
        }
    }
}

class Conversation_RoleTests_Quick_Nimble: QuickSpec {
    override func spec() {
        describe(".requestForUpdatingParticipantRole") {
            
            context("I don't have the required parameters") {
                it("should fail") {}
            }
            
            context("I have the parameters") {
            
                context("the response status is sucessful") {
                    
                    it("adds participant and updates conversation state") {
                        
                    }
                    
                    it("completes with success") {
                        
                    }
                }
                
                context("the response status is not sucessful") {
                    
                    it("completes with failure") {
                        
                    }
                }
            }
        }
    }
}
