//
//  Conversation_RoleTests_Quick_Nimble.swift
//  WireSyncEngine-iOS-Tests
//
//  Created by David Henner on 25.11.20.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Quick
import Nimble
@testable import WireSyncEngine

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
    
    typealias Factory = WireSyncEngine.ConversationRoleRequestFactory
    
    var contextDirectory: ManagedObjectContextDirectory?
    
    override func spec() {
        beforeSuite {
            let group = DispatchGroup()
            group.enter()
            
            var documentsDirectory: URL?
            StorageStack.reset()
            StorageStack.shared.createStorageAsInMemory = true
            do {
                documentsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            } catch {
                XCTAssertNil(error, "Unexpected error \(error)")
            }
            StorageStack.shared.createManagedObjectContextDirectory(accountIdentifier: UUID(), applicationContainer: documentsDirectory!) {
                self.contextDirectory = $0
                group.leave()
            }
            group.wait()
        }
        
        var uiMOC: NSManagedObjectContext {
            return self.contextDirectory!.uiContext
        }
        
        describe(".requestForUpdatingParticipantRole") {
            
            context("I don't have the required parameters") {
                 it("should fail") {}
            }
            
            context("inputs are valid") {
                var user: ZMUser!
                var conversation: ZMConversation!
                var role: Role!
                
                beforeEach {
                    user = ZMUser.insertNewObject(in: uiMOC)
                    user.remoteIdentifier = UUID.create()
                    
                    conversation = ZMConversation.insertNewObject(in: uiMOC)
                    conversation.remoteIdentifier = UUID.create()
                    
                    role = Role.insertNewObject(in: uiMOC)
                    role.name = "wire_admin"
                }
                
                it("return the correct request") {
                    var result: VoidResult?
                    
                    guard let request = Factory.requestForUpdatingParticipantRole(role, for: user, in: conversation, completion: {
                        result = $0
                    })
                    else {
                        return fail("Could not create request")
                    }
                
                    expect(result).toEventually(be(VoidResult.success))
                    
                    expect(request.path).to(equal("/conversations/\(conversation.remoteIdentifier!.transportString())/members/\(user.remoteIdentifier!.transportString())"))
                    
                    expect(request.method).to(equal(.methodPUT))
                    expect(request.payload?.asDictionary() as? [String: String]).to(equal(["conversation_role": "wire_admin"]))
                }
                
                context("request is completed") {
                    it("completes with success") {
                        
                    }
                    
                    it("updates participant roles in Database") {
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
