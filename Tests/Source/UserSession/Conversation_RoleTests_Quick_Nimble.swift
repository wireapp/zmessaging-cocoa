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
        
        describe("requestForUpdatingParticipantRole") {
            var user: ZMUser!
            var conversation: ZMConversation!
            var role: Role!
            var request: ZMTransportRequest?
            var result: VoidResult?
            
            beforeEach {
                user = ZMUser.insertNewObject(in: uiMOC)
                user.remoteIdentifier = UUID.create()
                
                conversation = ZMConversation.insertNewObject(in: uiMOC)
                conversation.remoteIdentifier = UUID.create()
                
                role = Role.insertNewObject(in: uiMOC)
                role.name = "wire_admin"
            }
            
            afterEach {
                user = nil
                conversation = nil
                role = nil
            }
            
            it("fails when role name is missing") {
                // GIVEN
                role.name = nil
                
                // WHEN
                request = Factory.requestForUpdatingParticipantRole(
                    role,
                    for: user,
                    in: conversation,
                    completion: {
                        result = $0
                })
                
                // THEN
                expect(request).to(beNil())
            }
                
            it("fails when user id is missing") {
                // GIVEN
                user.remoteIdentifier = nil
               
                // WHEN
                request = Factory.requestForUpdatingParticipantRole(
                    role,
                    for: user,
                    in: conversation,
                    completion: {
                        result = $0
                })
                
                // THEN
                expect(request).to(beNil())
            }
                
            it("fails when conversation id is missing") {
                // GIVEN
                conversation.remoteIdentifier = nil
                
                // WHEN
                request = Factory.requestForUpdatingParticipantRole(
                    role,
                    for: user,
                    in: conversation,
                    completion: {
                        result = $0
                })
                
                // THEN
                expect(request).to(beNil())
            }
            
            context("inputs are valid") {
                beforeEach {
                    request = Factory.requestForUpdatingParticipantRole(
                        role,
                        for: user,
                        in: conversation,
                        completion: {
                            result = $0
                    })
                }
                
                afterEach {
                    request = nil
                }
                
                it("returns the correct request") {
                    expect(request?.path).to(equal("/conversations/\(conversation.remoteIdentifier!.transportString())/members/\(user.remoteIdentifier!.transportString())"))
                    
                    expect(request?.method).to(equal(.methodPUT))
                    expect(request?.payload?.asDictionary() as? [String: String]).to(equal(["conversation_role": "wire_admin"]))
                }
                
                context("response status is successful") {
                    beforeEach {
                        request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
                    }
                    
                    it("completes with success") {
                        testCompletionResult(isSuccess: true)
                    }
                    
                    it("updates participant roles in database") {
                        expect(
                            user.participantRoles.first { $0.conversation == conversation }?.role
                        ).toEventually(equal(role))
                    }
                }
               
                context("response status is not sucessful") {
                    beforeEach {
                        request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil))
                    }
                    
                    it("completes with failure") {
                       testCompletionResult(isSuccess: false)
                    }
                    
                    it("does not update database") {
                        expect(user.participantRoles).toEventually(beEmpty())
                    }
                }
                
                func testCompletionResult(isSuccess: Bool) {
                    expect({
                        let block: (Bool) -> (() -> (ToSucceedResult)) = { isSuccess in
                            return { isSuccess ? .succeeded : .failed(reason: "wrong enum case") }
                        }
                        
                        guard let result = result else {
                            return { .failed(reason: "result is nil") }
                        }
                        switch result {
                        case .success:
                            return block(isSuccess)
                        case .failure:
                            return block(!isSuccess)
                        }
                    }).toEventually(succeed())
                }
            }
        }
    }
}
