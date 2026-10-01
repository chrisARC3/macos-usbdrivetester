//
//  RunIDWireTests.swift
//  USBDriveTesterTests
//
//  Protocol v16 (Step 15 chunk 4): the run ID's wire type and its one spelling in the log. The
//  controller's half — one ID per authorisation, handed to the acquire — is
//  `RunControllerRunIDTests`. The helper's half, stamping it on its lines, is not in the test
//  target; chunk 5's traced run reads it off the log.
//

import Testing
import Foundation
@testable import USBDriveTester

struct RunIDWireTests {

    /// The ID crosses XPC as `NSUUID`, so XPC's own decoding is what rejects a malformed one and
    /// no caller-controlled text reaches the root daemon's log through it. This reads what the
    /// interface the app and the helper both build will accept for that argument.
    @Test func acquireDeviceCarriesTheRunIDAsAUUID() {
        let interface = NSXPCInterface(with: TesterControl.self)
        let classes = interface.classes(
            for: #selector(TesterControl.acquireDevice(bsdName:runID:reply:)),
            argumentIndex: 1,
            ofReply: false)
        #expect(classes.contains { ($0 as? AnyClass) == NSUUID.self })
        #expect(!classes.contains { ($0 as? AnyClass) == NSString.self },
                "a string here would let any text through to the helper's log")
    }

    /// One spelling in both processes: a search for the ID is a search for this.
    @Test func theTagNamesTheRunByItsFullUUID() throws {
        let id = try #require(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        #expect(TesterProtocol.runTag(id) == "[run E621E1F8-C36C-495A-93FC-0C247A3E6E5F] ")
    }

    /// No run, no tag — not `[run nil]`, which a search for a real ID could never find but a
    /// search for `[run` would.
    @Test func noRunIsNoTag() {
        #expect(TesterProtocol.runTag(nil) == "")
    }
}
