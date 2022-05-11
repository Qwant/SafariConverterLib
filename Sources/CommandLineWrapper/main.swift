import Foundation
import ContentBlockerConverter
import Shared
import ArgumentParser

let fm = FileManager.default
let fallbackPath: String = (#file as NSString).deletingLastPathComponent + "/../.."
// We expect this command to be executed as 'cd <dir of swift package>; swift run', if not, use the fallback path generated from the path to main.swift. Running from an xcodeproj will use fallbackPath.
let execIsFromCorrectDir = fm.fileExists(atPath: fm.currentDirectoryPath + "/Package.swift")
let rootDir = execIsFromCorrectDir ? fm.currentDirectoryPath : fallbackPath
let root = URL(fileURLWithPath: "\(rootDir)/..")

func encodeJson(_ result: String) throws -> String {
    return try result.data(using: .utf8, allowLossyConversion: false)!.prettyPrinted()
}

/**
 * Converter tool
 * Usage:
 *  "cat rules.txt | ./ConverterTool --safari-version 14 --optimize true --advanced-blocking true --advanced-blocking-format txt --output-file-name list"
 */
struct ConverterTool: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ConverterTool")

    @Option(name: .shortAndLong, help: "Safari version.")
    var safariVersion: Double = 13

    @Option(name: .shortAndLong, help: "Optimize.")
    var optimize = false

    @Option(name: .shortAndLong, help: "Advanced blocking.")
    var advancedBlocking = false

    @Option(name: .shortAndLong, help: "Maximum json size in bytes. Leave empty for no limit.")
    var maxJsonSizeBytes: Int = 0

    @Option(name: [.customShort("f"), .long], help: "Advanced blocking output format.")
    var advancedBlockingFormat = "json"

    @Option(name: [.customShort("n"), .long], help: "Name of the output file.")
    var outputFileName = "unnamed_list"

    @Argument(help: "Reads rules from standard input.")
    var rules: String?

    mutating func run() throws {
        let safariVersionResolved = SafariVersion(safariVersion);

        guard let advancedBlockingFormat = AdvancedBlockingFormat(rawValue: advancedBlockingFormat) else {
            throw AdvancedBlockingFormatError.unsupportedFormat()
        }

        let maxJsonSizeBytesOption: Int? = (maxJsonSizeBytes <= 0) ? nil : maxJsonSizeBytes

        Logger.log("(ConverterTool) - Safari version: \(safariVersionResolved)")
        Logger.log("(ConverterTool) - Optimize: \(optimize)")
        Logger.log("(ConverterTool) - Advanced blocking: \(advancedBlocking)")
        Logger.log("(ConverterTool) - Advanced blocking format: \(advancedBlockingFormat)")

        if let size = maxJsonSizeBytesOption {
            Logger.log("(ConverterTool) - Max json limit: \(size)")
        } else {
            Logger.log("(ConverterTool) - Max json limit: No limit set")
        }

        var rules: [String] = []
        var line: String?
        while true {
            line = readLine(strippingNewline: true)
            guard let unwrappedLine = line, !unwrappedLine.isEmpty else {
                break
            }

            rules.append(unwrappedLine)
        }

        Logger.log("(ConverterTool) - Rules to convert: \(rules.count)")

        let result: ConversionResult = ContentBlockerConverter()
            .convertArray(
                rules: rules,
                safariVersion: safariVersionResolved,
                optimize: optimize,
                advancedBlocking: advancedBlocking,
                advancedBlockingFormat: advancedBlockingFormat,
                maxJsonSizeBytes: maxJsonSizeBytesOption
            )

        Logger.log("(ConverterTool) - Conversion done.")

        let encoded = try encodeJson(result.converted)
        let path = root.appendingPathComponent(outputFileName).appendingPathExtension("json")
        try encoded.write(to: path)
    }
}

ConverterTool.main()

private extension String {
    func write(to url: URL) throws {
        if let data = self.data(using: .utf8, allowLossyConversion: false) {
            try data.createOrAppend(at: url)
        }
    }
}

private extension Data {
    func createOrAppend(at url: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: url.path) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
            fileHandle.closeFile()
        } else {
            try String(data: self, encoding: .utf8)?.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func prettyPrinted() throws -> String {
        let object = try JSONSerialization.jsonObject(with: self, options: [])
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8)!
    }
}
