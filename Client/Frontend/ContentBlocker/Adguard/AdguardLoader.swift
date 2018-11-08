//
//  AdguardLoader.swift
//  Client
//
//  Created by Zach McGaughey on 10/14/18.
//  Copyright © 2018 Mozilla. All rights reserved.
//

import UIKit
import PromiseKit
import WebKit
import Alamofire
import XCGLogger
import Shared

enum Errors: Error {
    case requestFailed
    case noRules
    case parseError
    case webkitError
    case notFound
}

private let log = Logger.customLogger

@available(iOS 11.0, *)
class AdguardLoader: NSObject {

    static let shared = AdguardLoader()

    private let parser = Parser()
    private let lists: [(String, String)]

    private override init() {
        lists = [
            ("AdGuard Base filter", "http://testfilters.adtidy.org/ios/filters/2_optimized.txt"),
            ("AdGuard Mobile Ads filter", "http://testfilters.adtidy.org/ios/filters/11_optimized.txt"),
            ("AdGuard Spyware filter", "http://testfilters.adtidy.org/ios/filters/3_optimized.txt"),
            ("AdGuard Annoyances filter", "http://testfilters.adtidy.org/ios/filters/14_optimized.txt"),
            ("AdGuard Safari filter", "http://testfilters.adtidy.org/ios/filters/12_optimized.txt")
        ]
    }

    func getLists(forceRefresh: Bool = false) -> Promise<[WKContentRuleList]> {

        let cached = checkForValidCache()
        if cached.isEmpty == false && !forceRefresh {
            log.info("adguard loading from cached values")
            let promises = cached.map({ lookupCached(identifier: $0, fileUrl: $1) })

            return firstly {
                when(resolved: promises)

            }.map { results -> [WKContentRuleList] in

                var values: [WKContentRuleList] = []

                for result in results {
                    switch result {
                    case .fulfilled(let value):
                        values.append(value)
                    case .rejected(_):
                        throw Errors.notFound
                    }
                }
                return values
            }.recover { error -> Promise<[WKContentRuleList]> in
                guard forceRefresh == false else { throw error }

                log.warning("cached adguard lists returned error, loading from network \(error)")
                return self.getLists(forceRefresh: true)
            }
        }

        // No cache, do fresh load

        let promises: [Promise<WKContentRuleList>] = lists.map { loadBlockList(identifier: $0.0, urlString: $0.1) }

        return firstly {
            when(resolved: promises)

        }.map { results -> [WKContentRuleList] in

            var values: [WKContentRuleList] = []

            for result in results {
                switch result {
                case .fulfilled(let value):
                    values.append(value)
                case .rejected(_):
                    throw Errors.notFound
                }
            }
            return values
        }
    }

    private func checkForValidCache() -> [(String, URL)] {
        let files = lists.map { $0.0.appending(".json") }
        let manager = FileManager.default

        // 7 days ago
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        var returnUrls: [(String, URL)] = []

        if let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {

            for file in files {

                let fileUrl = documentDir.appendingPathComponent(file)

                guard manager.fileExists(atPath: fileUrl.path) else { return [] }
                guard let attributes = try? manager.attributesOfItem(atPath: fileUrl.path) else { return [] }
                if let modified = attributes[.modificationDate] as? Date {
                    guard modified >= oneWeekAgo else {
                        log.debug("found cached files, but older than 1 week, refreshing")
                        return []
                    }
                }

                let fileName = String(fileUrl.lastPathComponent.split(separator: ".").first!)
                returnUrls.append((fileName, fileUrl))
            }

            return returnUrls
        }
        return []
    }

    private func loadBlockList(identifier: String, urlString: String) -> Promise<WKContentRuleList> {
        log.debug("loading block list: \(identifier), \(urlString)")
        return firstly {
            fetchUrl(URL(string: urlString)!)

            }.map(on: DispatchQueue.global(qos: .userInitiated)) { rules -> String in
                do {
                    let jsonString = try self.parseRules(rules)
                    return jsonString

                } catch {
                    throw error
                }

            }.get { jsonRule in
                self.saveToFile(identifier: identifier, jsonString: jsonRule)

            }.then { jsonString -> Promise<WKContentRuleList> in
                self.createListStore(identifier: identifier, jsonString: jsonString)
        }
    }

    private func saveToFile(identifier: String, jsonString: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileUrl = directory.appendingPathComponent(identifier + ".json")
        do {
            try jsonString.write(to: fileUrl, atomically: false, encoding: .utf8)
        } catch {
            log.error("failed to write adgaurd json to file: \(error)")
        }
    }

    private func lookupCached(identifier: String, fileUrl: URL) -> Promise<WKContentRuleList> {
        let identifier = identifier.replacingOccurrences(of: " ", with: "-")
        let store = WKContentRuleListStore.default()!

        return Promise { seal in

            store.lookUpContentRuleList(forIdentifier: identifier, completionHandler: { (list, error) in
                if let list = list {
                    return seal.fulfill(list)
                }

                guard let jsonData = try? String(contentsOf: fileUrl) else { return seal.reject(Errors.notFound )}

                store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: jsonData) { (list, error) in
                    guard let list = list else { return seal.reject(Errors.notFound) }
                    seal.fulfill(list)
                }

            })
        }
    }

    private func fetchUrl(_ url: URL) -> Promise<[String]> {

        return Promise<[String]> { seal in

            Alamofire.request(url).responseString { (response) in
                guard let string = response.value else { return seal.reject(Errors.requestFailed) }

                let components = string.components(separatedBy: CharacterSet.newlines).filter({ !$0.starts(with: "!") && !$0.isEmpty })

                guard components.isEmpty == false else { return seal.reject(Errors.noRules) }
                seal.fulfill(components)
            }
        }
    }

    private func parseRules(_ rules: [String]) throws -> String {
        let ruleDictionary = parser.json(fromRules: rules, upTo: 50000, optimize: true)
        guard let jsonString = ruleDictionary["converted"] as? String else { throw Errors.parseError }
        return jsonString
    }

    private func createListStore(identifier: String, jsonString: String) -> Promise<WKContentRuleList> {
        let identifier = identifier.replacingOccurrences(of: " ", with: "-")
        guard let store = WKContentRuleListStore.default() else { return Promise(error: Errors.webkitError) }

        return Promise { seal in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: jsonString) { (ruleList, error) in
                guard let ruleList = ruleList else { return seal.reject(Errors.webkitError) }
                log.debug("compiled list store for \(identifier)")
                seal.fulfill(ruleList)
            }
        }

    }

}
