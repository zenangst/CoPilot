//
//  CoPilotPluginTests.swift
//  CoPilotPluginTests
//
//  Created by Sven Schmidt on 18/04/2015.
//  Copyright (c) 2015 feinstruktur. All rights reserved.
//

import Cocoa
import XCTest
import Nimble

import CryptoSwift
import FeinstrukturUtils


func diff(a: String?, b: String?, checklines: Bool = true, deadline: NSTimeInterval = 1) -> [Diff] {
    let dmp = DiffMatchPatch()
    if let diffs = dmp.diff_mainOfOldString(a, andNewString: b, checkLines: checklines, deadline: deadline) {
        return NSArray(array: diffs) as! [Diff]
    } else {
        return [Diff]()
    }
}


func patch(diffs: [Diff]) -> [Patch] {
    let dmp = DiffMatchPatch()
    if let patches = dmp.patch_makeFromDiffs(NSMutableArray(array: diffs)) {
        return NSArray(array: patches) as! [Patch]
    } else {
        return [Patch]()
    }
}


func apply(source: String, patches: [Patch]) -> Result<String> {
    let dmp = DiffMatchPatch()
    if let res = dmp.patch_apply(NSArray(array: patches) as [AnyObject], toString: source) {
        assert(res.count == 2, "results array must have two entries: (text, results)")
        if let target = res[0] as? String {
            let results = res[1] as! NSArray
            let success = reduce(results, true) { (res, elem) in res && (elem as! NSNumber).boolValue }
            if success {
                return Result(target)
            }
        }
    }
    return Result(NSError())
}


struct Changeset {
    let patches: [Patch]
    let baseRev: Hash
    let targetRev: Hash
}


func apply(source: Document, changeSet: Changeset) -> Result<Document> {
    if source.hash == changeSet.baseRev {
        // this should apply cleanly
        switch apply(source.text, changeSet.patches) {
        case .Success(let value):
            let target = Document(text: value.unbox)
            assert(target.hash == changeSet.targetRev)
            return Result(target)
        case .Failure(let error):
            return Result(error)
        }
    } else {
        // we have local changes
        // try applying this but it might fail
        let res = apply(source.text, changeSet.patches)
        return map(res) { Document(text: $0) }
    }
}


typealias Hash = String


struct Document {
    var text: String
    var hash: Hash {
        return self.text.md5()!
    }
}


class CoPilotPluginTests: XCTestCase {
    
    func test_diff() {
        let d = diff("foo2bar", "foobar")
        expect(d.count) == 3
        expect(d[0].operation) == Operation.DiffEqual
        expect(d[0].text) == "foo"
        expect(d[1].operation) == Operation.DiffDelete
        expect(d[1].text) == "2"
        expect(d[2].operation) == Operation.DiffEqual
        expect(d[2].text) == "bar"
    }
    
    
    func test_patches() {
        let diffs = diff("foo2bar", "foobar")
        let patches = patch(diffs)
        expect(patches.count) == 1
        let lines = patches[0].description.componentsSeparatedByString("\n")
        expect(lines[0]) == "@@ -1,7 +1,6 @@"
        expect(lines[1]) == " foo"
        expect(lines[2]) == "-2"
        expect(lines[3]) == " bar"
        expect(patches[0].start1) == 0
        expect(patches[0].start2) == 0
        expect(patches[0].length1) == 7
        expect(patches[0].length2) == 6
    }
    
    
    func test_apply_String() {
        let diffs = diff("foo2bar", "foobar")
        let patches = patch(diffs)
        let res = apply("foo2bar", patches)
        expect(res.succeeded) == true
        expect(res.value!) == "foobar"
    }
    
    
    func test_apply_Document() {
        let source = Document(text: "The quick brown fox jumps over the lazy dog")
        let newText = "The quick brown cat jumps over the lazy dog"
        let diffs = diff(source.text, newText)
        let patches = patch(diffs)
        let changeSet = Changeset(patches: patches, baseRev: source.hash, targetRev: newText.md5()!)
        let res = apply(source, changeSet)
        expect(res.succeeded) == true
        expect(res.value!.text) == newText
    }
    
    
    func test_hash() {
        let doc = Document(text: "The quick brown fox jumps over the lazy dog")
        expect(doc.hash) == "9e107d9d372bb6826bd81d3542a419d6".uppercaseString
    }
    
}
