// PiPiBot — Clean-room MIT implementation.
// Universal local office & document text extractor for everyday C-end office workflows:
// - WPS Office: .wps, .wpt, .et, .ett, .dps, .dpt
// - Microsoft Office: .docx, .doc, .xlsx (structured table reconstruction), .xls, .pptx, .ppt
// - Apple iWork: .pages, .numbers, .key
// - OpenDocument & Rich Text: .odt, .ods, .odp, .rtf, .rtfd, .html, .htm, .eml
// - PDF: native PDFKit + Apple Vision on-device OCR fallback for scanned Chinese/English PDFs
// - Plain Text / Tables / Code: .txt, .csv, .tsv, .md, .json, .xml (UTF-8 / UTF-16 / GB18030)

import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision) && canImport(AppKit)
import Vision
import AppKit
#endif

public enum PipiDocumentExtractor {
    /// Maximum on-disk file size we attempt to extract text from (30 MB).
    public static let maxExtractableFileBytes: Int = 30 * 1024 * 1024
    /// Maximum extracted characters injected into an LLM prompt by default.
    public static let defaultMaxChars: Int = 24_000

    private static let nonTextMediaExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "ico",
        "mp4", "mov", "mkv", "avi", "webm", "m4v",
        "mp3", "wav", "m4a", "aac", "ogg", "flac", "silk", "amr",
        "zip", "tar", "gz", "7z", "rar", "dmg", "pkg", "app", "ipa", "exe", "bin", "dylib", "o"
    ]

    public static let officeAndRichDocExtensions: Set<String> = [
        // WPS Office
        "wps", "wpt", "et", "ett", "dps", "dpt",
        // Microsoft Office
        "docx", "doc", "xlsx", "xls", "pptx", "ppt",
        // Apple iWork
        "pages", "numbers", "key",
        // OpenDocument, PDF, Rich Text & Email
        "odt", "ods", "odp", "pdf", "rtf", "rtfd", "html", "htm", "xml", "eml"
    ]

    /// Extracts readable plain text from local office documents, PDFs (including scanned PDFs via Vision OCR),
    /// and plain text/CSV/code files (including GB18030/GBK Chinese encodings).
    public static func extractText(from url: URL, maxChars: Int = defaultMaxChars) -> String? {
        let fm = FileManager.default
        let path = url.path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return nil
        }

        let ext = url.pathExtension.lowercased()
        // Package-based formats on macOS (.rtfd, .pages, .numbers, .key) can be directories
        let allowPackageDir = ["rtfd", "pages", "numbers", "key"].contains(ext)
        if isDir.boolValue && !allowPackageDir {
            return nil
        }
        if nonTextMediaExtensions.contains(ext) {
            return nil
        }

        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= maxExtractableFileBytes else {
                return nil
            }
        }

        let raw: String? = {
            switch ext {
            case "pdf":
                return extractPDF(url: url)
            case "docx":
                return extractOOXMLZip(url: url, kind: .docx) ?? runTextUtil(path: path, forcedFormat: nil)
            case "xlsx":
                return extractOOXMLZip(url: url, kind: .xlsx) ?? querySpotlightText(path: path)
            case "pptx":
                return extractOOXMLZip(url: url, kind: .pptx) ?? querySpotlightText(path: path)
            case "odt", "ods", "odp":
                return extractOOXMLZip(url: url, kind: .odt) ?? runTextUtil(path: path, forcedFormat: ext == "odt" ? "odt" : nil)
            case "doc":
                return runTextUtil(path: path, forcedFormat: "doc")
                    ?? querySpotlightText(path: path)
                    ?? extractOLE2FallbackText(url: url)
            case "xls", "ppt":
                return querySpotlightText(path: path) ?? extractOLE2FallbackText(url: url)
            case "rtf", "rtfd":
                return runTextUtil(path: path, forcedFormat: ext) ?? decodePlainText(url: url)
            case "wps", "wpt":
                return extractWPSOffice(url: url, preferredZipKind: .docx)
            case "et", "ett":
                return extractWPSOffice(url: url, preferredZipKind: .xlsx)
            case "dps", "dpt":
                return extractWPSOffice(url: url, preferredZipKind: .pptx)
            case "pages", "numbers", "key":
                return extractAppleIWork(url: url)
            case "html", "htm":
                return runTextUtil(path: path, forcedFormat: "html") ?? stripXMLTags(decodePlainText(url: url) ?? "")
            case "eml":
                return extractEML(url: url)
            default:
                // Plain text / code / csv / tsv / markdown / json — UTF-8, UTF-16, GB18030
                return decodePlainText(url: url)
            }
        }()

        guard let raw else { return nil }
        let isRichDoc = officeAndRichDocExtensions.contains(ext)
        let finalText = isRichDoc ? normalizeWhitespace(raw) : raw
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if finalText.count > maxChars {
            return String(finalText.prefix(maxChars)) + "\n…（内容较长，已截取前 \(maxChars) 字）"
        }
        return finalText
    }

    /// Runs on-device Apple Vision OCR on an image file (useful for photos of contracts, receipts, screenshots).
    public static func extractTextFromImage(url: URL, maxChars: Int = 8_000) -> String? {
        #if canImport(Vision) && canImport(AppKit)
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        guard let text = recognizeText(in: cgImage), !text.isEmpty else { return nil }
        let normalized = normalizeWhitespace(text)
        guard !normalized.isEmpty else { return nil }
        return normalized.count > maxChars ? String(normalized.prefix(maxChars)) + "\n…（已截断）" : normalized
        #else
        return nil
        #endif
    }

    // MARK: - Kingsoft WPS Office (.wps/.wpt, .et/.ett, .dps/.dpt)

    private static func extractWPSOffice(url: URL, preferredZipKind: ZipDocKind) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }

        // 1. Modern WPS Office files are often ZIP/OOXML packages (magic: PK\x03\x04)
        if data.count >= 4,
           data[0] == 0x50, data[1] == 0x4B, data[2] == 0x03, data[3] == 0x04 {
            if let text = extractOOXMLZip(url: url, kind: preferredZipKind), !text.isEmpty {
                return text
            }
            if let text = extractAnyXMLFromZip(url: url), !text.isEmpty {
                return text
            }
        }

        // 2. RTF-backed .wps (magic: {\rtf)
        if let head = String(data: data.prefix(32), encoding: .ascii)?.lowercased(),
           head.contains("{\\rtf") {
            if let text = runTextUtil(path: url.path, forcedFormat: "rtf"), !text.isEmpty {
                return text
            }
        }

        // 3. HTML / XML-backed .wps / .et
        if let head = String(data: data.prefix(256), encoding: .utf8)?.lowercased(),
           head.contains("<html") || head.contains("<!doctype html") || head.contains("<?xml") {
            if let text = runTextUtil(path: url.path, forcedFormat: "html"), !text.isEmpty {
                return text
            }
            if let decoded = decodePlainTextData(data) {
                let stripped = stripXMLTags(decoded)
                if !stripped.isEmpty { return stripped }
            }
        }

        // 4. OLE2 Compound Binary (magic: D0 CF 11 E0 A1 B1 1A E1)
        let isOLE2 = data.count >= 8
            && data[0] == 0xD0 && data[1] == 0xCF && data[2] == 0x11 && data[3] == 0xE0
            && data[4] == 0xA1 && data[5] == 0xB1 && data[6] == 0x1A && data[7] == 0xE1

        if isOLE2 {
            if preferredZipKind == .docx,
               let text = runTextUtil(path: url.path, forcedFormat: "doc"),
               isMeaningfulDocumentText(text) {
                return text
            }
            if let mdText = querySpotlightText(path: url.path), isMeaningfulDocumentText(mdText) {
                return mdText
            }
            if let recovered = extractOLE2ReadableRuns(from: data), !recovered.isEmpty {
                return recovered
            }
        }

        // 5. Fallback: Spotlight or plain text decoding
        if let mdText = querySpotlightText(path: url.path), isMeaningfulDocumentText(mdText) {
            return mdText
        }
        if let plain = decodePlainTextData(data), isMeaningfulDocumentText(plain) {
            return plain
        }
        return nil
    }

    // MARK: - Apple iWork (.pages / .numbers / .key)

    private static func extractAppleIWork(url: URL) -> String? {
        // 1. Spotlight indexed text (fastest and cleanest on macOS)
        if let mdText = querySpotlightText(path: url.path), isMeaningfulDocumentText(mdText) {
            return mdText
        }
        // 2. Package directory: check embedded QuickLook/Preview.pdf or preview.pdf
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            for rel in ["QuickLook/Preview.pdf", "preview.pdf"] {
                let pdfURL = url.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: pdfURL.path),
                   let text = extractPDF(url: pdfURL), !text.isEmpty {
                    return text
                }
            }
        }
        // 3. Single-file ZIP iWork archive: extract QuickLook/Preview.pdf via unzip
        #if os(macOS)
        let entries = listZipEntries(zipPath: url.path)
        if let pdfEntry = entries.first(where: { $0.lowercased().hasSuffix("preview.pdf") }) {
            let tmpPDF = FileManager.default.temporaryDirectory
                .appendingPathComponent("pipi-iwork-\(UUID().uuidString.prefix(8)).pdf")
            defer { try? FileManager.default.removeItem(at: tmpPDF) }
            if let data = runProcessRaw(executable: "/usr/bin/unzip", arguments: ["-p", url.path, pdfEntry]),
               !data.isEmpty {
                try? data.write(to: tmpPDF)
                if let text = extractPDF(url: tmpPDF), !text.isEmpty {
                    return text
                }
            }
        }
        #endif
        return nil
    }

    // MARK: - Email (.eml)

    private static func extractEML(url: URL) -> String? {
        guard let raw = decodePlainText(url: url), !raw.isEmpty else { return nil }
        // Keep key headers (Subject, From, To, Date) + body
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let fallbackParts = parts.count > 1 ? parts : raw.components(separatedBy: "\n\n")
        guard fallbackParts.count >= 2 else { return stripXMLTags(raw) }
        let headerBlock = fallbackParts[0]
        let keptHeaders = headerBlock
            .components(separatedBy: .newlines)
            .filter { line in
                let lower = line.lowercased()
                return lower.hasPrefix("subject:") || lower.hasPrefix("from:")
                    || lower.hasPrefix("to:") || lower.hasPrefix("date:")
            }
            .joined(separator: "\n")
        let body = fallbackParts.dropFirst().joined(separator: "\n\n")
        let cleanedBody = body.lowercased().contains("<html") || body.lowercased().contains("<div")
            ? stripXMLTags(body)
            : body
        return keptHeaders.isEmpty ? cleanedBody : "\(keptHeaders)\n\n\(cleanedBody)"
    }

    // MARK: - PDF (Native PDFKit + Apple Vision On-Device OCR Fallback for Scanned PDFs)

    private static func extractPDF(url: URL) -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        var chunks: [String] = []
        let limitPages = min(doc.pageCount, 80)
        for idx in 0..<limitPages {
            if let pageText = doc.page(at: idx)?.string,
               !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(pageText)
            }
        }
        if !chunks.isEmpty {
            return chunks.joined(separator: "\n\n")
        }

        // Scanned PDF fallback: render up to 12 pages and run Apple Vision OCR (zh-Hans, zh-Hant, en-US)
        #if canImport(Vision) && canImport(AppKit)
        var ocrPages: [String] = []
        let ocrLimit = min(doc.pageCount, 12)
        for idx in 0..<ocrLimit {
            guard let page = doc.page(at: idx) else { continue }
            let thumb = page.thumbnail(of: NSSize(width: 1600, height: 2200), for: .mediaBox)
            if let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let pageOCR = recognizeText(in: cgImage),
               !pageOCR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ocrPages.append("【第 \(idx + 1) 页】\n\(pageOCR)")
            }
        }
        return ocrPages.isEmpty ? nil : ocrPages.joined(separator: "\n\n")
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }

    #if canImport(Vision) && canImport(AppKit)
    private static func recognizeText(in cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - OOXML / ODF ZIP Extraction (via macOS /usr/bin/unzip)

    private enum ZipDocKind {
        case docx
        case xlsx
        case pptx
        case odt
    }

    private static func extractOOXMLZip(url: URL, kind: ZipDocKind) -> String? {
        #if os(macOS)
        switch kind {
        case .docx:
            guard let xml = runUnzipPipe(zipPath: url.path, entry: "word/document.xml") else { return nil }
            let text = stripOOXMLDocumentTags(xml)
            return text.isEmpty ? nil : text

        case .odt:
            guard let xml = runUnzipPipe(zipPath: url.path, entry: "content.xml") else { return nil }
            let text = stripOOXMLDocumentTags(xml)
            return text.isEmpty ? nil : text

        case .xlsx:
            let sharedStrings: [String] = {
                guard let xml = runUnzipPipe(zipPath: url.path, entry: "xl/sharedStrings.xml") else { return [] }
                return parseXLSXSharedStrings(xml)
            }()
            let entries = listZipEntries(zipPath: url.path)
                .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
                .sorted()
            var sheets: [String] = []
            for (idx, entry) in entries.prefix(8).enumerated() {
                if let sheetXml = runUnzipPipe(zipPath: url.path, entry: entry) {
                    let rendered = parseXLSXWorksheet(sheetXml, sharedStrings: sharedStrings)
                    if !rendered.isEmpty {
                        sheets.append("【工作表 \(idx + 1)】\n\(rendered)")
                    }
                }
            }
            if !sheets.isEmpty {
                return sheets.joined(separator: "\n\n")
            }
            return sharedStrings.isEmpty ? nil : sharedStrings.joined(separator: "\n")

        case .pptx:
            let entries = listZipEntries(zipPath: url.path)
                .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                .sorted { lhs, rhs in
                    let n1 = Int(lhs.filter(\.isNumber)) ?? 0
                    let n2 = Int(rhs.filter(\.isNumber)) ?? 0
                    return n1 < n2
                }
            var slides: [String] = []
            for (idx, entry) in entries.prefix(60).enumerated() {
                if let slideXml = runUnzipPipe(zipPath: url.path, entry: entry) {
                    let text = stripOOXMLDocumentTags(slideXml)
                    if !text.isEmpty {
                        slides.append("【幻灯片 \(idx + 1)】\n\(text)")
                    }
                }
            }
            return slides.isEmpty ? nil : slides.joined(separator: "\n\n")
        }
        #else
        return nil
        #endif
    }

    private static func parseXLSXSharedStrings(_ xml: String) -> [String] {
        var results: [String] = []
        var searchRange = xml.startIndex..<xml.endIndex
        while let start = xml.range(of: "<si", range: searchRange),
              let openEnd = xml.range(of: ">", range: start.upperBound..<xml.endIndex),
              let end = xml.range(of: "</si>", range: openEnd.upperBound..<xml.endIndex) {
            let inner = String(xml[openEnd.upperBound..<end.lowerBound])
            results.append(stripXMLTags(inner).trimmingCharacters(in: .whitespacesAndNewlines))
            searchRange = end.upperBound..<xml.endIndex
        }
        return results
    }

    private static func parseXLSXWorksheet(_ xml: String, sharedStrings: [String]) -> String {
        var rows: [String] = []
        var rowRange = xml.startIndex..<xml.endIndex
        while let rStart = xml.range(of: "<row", range: rowRange),
              let rOpenEnd = xml.range(of: ">", range: rStart.upperBound..<xml.endIndex),
              let rEnd = xml.range(of: "</row>", range: rOpenEnd.upperBound..<xml.endIndex) {
            let rowInner = String(xml[rOpenEnd.upperBound..<rEnd.lowerBound])
            var cells: [String] = []
            var cellRange = rowInner.startIndex..<rowInner.endIndex
            while let cStart = rowInner.range(of: "<c ", range: cellRange) ?? rowInner.range(of: "<c>", range: cellRange),
                  let cTagEnd = rowInner.range(of: ">", range: cStart.upperBound..<rowInner.endIndex),
                  let cEnd = rowInner.range(of: "</c>", range: cTagEnd.upperBound..<rowInner.endIndex) {
                let tagHeader = String(rowInner[cStart.lowerBound..<cTagEnd.upperBound])
                let cellInner = String(rowInner[cTagEnd.upperBound..<cEnd.lowerBound])
                let isShared = tagHeader.contains("t=\"s\"")
                let isInline = tagHeader.contains("t=\"inlineStr\"")
                var cellText = ""
                if isInline {
                    cellText = stripXMLTags(cellInner).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let vStart = cellInner.range(of: "<v>"),
                          let vEnd = cellInner.range(of: "</v>", range: vStart.upperBound..<cellInner.endIndex) {
                    let rawVal = String(cellInner[vStart.upperBound..<vEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isShared, let idx = Int(rawVal), idx >= 0, idx < sharedStrings.count {
                        cellText = sharedStrings[idx]
                    } else {
                        cellText = decodeXMLEntities(rawVal)
                    }
                }
                if !cellText.isEmpty {
                    cells.append(cellText)
                }
                cellRange = cEnd.upperBound..<rowInner.endIndex
            }
            if !cells.isEmpty {
                rows.append(cells.joined(separator: " | "))
            }
            if rows.count >= 300 { break }
            rowRange = rEnd.upperBound..<xml.endIndex
        }
        return rows.joined(separator: "\n")
    }

    private static func extractAnyXMLFromZip(url: URL) -> String? {
        #if os(macOS)
        let entries = listZipEntries(zipPath: url.path)
            .filter { $0.lowercased().hasSuffix(".xml") && !$0.contains("_rels") && !$0.contains("[Content_Types]") }
        for candidate in ["word/document.xml", "content.xml", "document.xml"] {
            if entries.contains(candidate), let xml = runUnzipPipe(zipPath: url.path, entry: candidate) {
                let text = stripOOXMLDocumentTags(xml)
                if !text.isEmpty { return text }
            }
        }
        for entry in entries.prefix(5) {
            if let xml = runUnzipPipe(zipPath: url.path, entry: entry) {
                let text = stripOOXMLDocumentTags(xml)
                if isMeaningfulDocumentText(text) { return text }
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private static func listZipEntries(zipPath: String) -> [String] {
        guard let output = runProcess(executable: "/usr/bin/unzip", arguments: ["-Z1", zipPath]) else {
            return []
        }
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func runUnzipPipe(zipPath: String, entry: String) -> String? {
        runProcess(executable: "/usr/bin/unzip", arguments: ["-p", zipPath, entry])
    }

    private static func runTextUtil(path: String, forcedFormat: String?) -> String? {
        var args: [String] = []
        if let forcedFormat, !forcedFormat.isEmpty {
            args.append(contentsOf: ["-format", forcedFormat])
        }
        args.append(contentsOf: ["-convert", "txt", "-stdout", path])
        return runProcess(executable: "/usr/bin/textutil", arguments: args)
    }

    private static func querySpotlightText(path: String) -> String? {
        guard let out = runProcess(executable: "/usr/bin/mdls", arguments: ["-raw", "-name", "kMDItemTextContent", path]) else {
            return nil
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(null)" { return nil }
        return trimmed
    }

    private static func runProcessRaw(executable: String, arguments: [String]) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10.0)
        timer.setEventHandler { if proc.isRunning { proc.terminate() } }
        timer.resume()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        timer.cancel()
        guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private static func runProcess(executable: String, arguments: [String]) -> String? {
        guard let data = runProcessRaw(executable: executable, arguments: arguments) else { return nil }
        return decodePlainTextData(data)
    }
    #else
    private static func runTextUtil(path: String, forcedFormat: String?) -> String? { nil }
    private static func querySpotlightText(path: String) -> String? { nil }
    #endif

    // MARK: - OLE2 Binary Readable Text Fallback (for proprietary .wps / legacy .doc / .xls / .ppt)

    private static func extractOLE2FallbackText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return extractOLE2ReadableRuns(from: data)
    }

    /// Scans an OLE2 binary buffer for contiguous UTF-16LE readable paragraphs (filtering out OLE headers/font tables).
    static func extractOLE2ReadableRuns(from data: Data) -> String? {
        guard data.count >= 16 else { return nil }

        let noiseMarkers: Set<String> = [
            "Root Entry", "WordDocument", "1Table", "0Table", "SummaryInformation",
            "DocumentSummaryInformation", "CompObj", "MsoDataStore", "Data", "ObjectPool",
            "Workbook", "PowerPoint Document", "Current User", "Pictures",
            "Times New Roman", "Calibri", "Cambria", "SimSun", "SimHei", "FangSong", "KaiTi",
            "Microsoft YaHei", "Arial", "Helvetica", "Normal", "Heading"
        ]

        var bestLines: [String] = []
        var seen: Set<String> = []

        for alignment in 0...1 {
            var currentScalars: [UnicodeScalar] = []
            currentScalars.reserveCapacity(256)

            func flushCurrent() {
                guard currentScalars.count >= 4 else {
                    currentScalars.removeAll(keepingCapacity: true)
                    return
                }
                let rawStr = String(String.UnicodeScalarView(currentScalars))
                currentScalars.removeAll(keepingCapacity: true)
                let lines = rawStr
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .components(separatedBy: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count >= 4 else { continue }
                    if noiseMarkers.contains(where: { trimmed.caseInsensitiveCompare($0) == .orderedSame }) {
                        continue
                    }
                    let hasCJK = trimmed.unicodeScalars.contains(where: isCJKScalar)
                    let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
                    guard hasCJK || (letterCount >= 8 && trimmed.contains(" ")) else { continue }
                    if seen.insert(trimmed).inserted {
                        bestLines.append(trimmed)
                    }
                }
            }

            var idx = alignment
            let limit = data.count - 1
            while idx < limit {
                let lo = UInt16(data[idx])
                let hi = UInt16(data[idx + 1])
                let codeUnit = lo | (hi << 8)
                idx += 2

                if let scalar = UnicodeScalar(codeUnit), isReadableDocScalar(scalar) {
                    currentScalars.append(scalar)
                } else {
                    flushCurrent()
                }
            }
            flushCurrent()
            if bestLines.count >= 3 { break }
        }

        let joined = bestLines.joined(separator: "\n")
        return isMeaningfulDocumentText(joined) ? joined : nil
    }

    private static func isCJKScalar(_ s: UnicodeScalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x3000...0x303F).contains(v)
            || (0xFF00...0xFFEF).contains(v)
    }

    private static func isReadableDocScalar(_ s: UnicodeScalar) -> Bool {
        let v = s.value
        if v == 0x0009 || v == 0x000A || v == 0x000D { return true }
        if (0x0020...0x007E).contains(v) { return true }
        if isCJKScalar(s) { return true }
        if (0x2000...0x206F).contains(v) { return true }
        return false
    }

    private static func isMeaningfulDocumentText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let readableCount = trimmed.unicodeScalars.filter { isReadableDocScalar($0) }.count
        return Double(readableCount) / Double(max(1, trimmed.unicodeScalars.count)) >= 0.8
    }

    // MARK: - XML / Plain Text Helpers (with GB18030 Chinese encoding fallback)

    private static func stripOOXMLDocumentTags(_ xml: String) -> String {
        var s = xml
        for breakTag in ["</w:p>", "</w:tr>", "</text:p>", "</a:p>", "</si>", "</row>", "<w:br/>", "<w:br />", "<br/>", "<br />"] {
            s = s.replacingOccurrences(of: breakTag, with: "\n")
        }
        s = s.replacingOccurrences(of: "<w:tab/>", with: "\t")
        s = s.replacingOccurrences(of: "</w:tc>", with: "\t")
        return stripXMLTags(s)
    }

    private static func stripXMLTags(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count / 2)
        var inTag = false
        for ch in input {
            if ch == "<" {
                inTag = true
            } else if ch == ">" {
                inTag = false
            } else if !inTag {
                result.append(ch)
            }
        }
        return decodeXMLEntities(result)
    }

    private static func decodeXMLEntities(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#xA;", with: "\n")
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#9;", with: "\t")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func decodePlainText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodePlainTextData(data)
    }

    private static func decodePlainTextData(_ data: Data) -> String? {
        if data.isEmpty { return nil }
        let hasUTF16BOM = data.count >= 2 && ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF))
        if hasUTF16BOM, let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        let sample = data.prefix(512)
        let nulCount = sample.filter { $0 == 0 }.count
        if nulCount > 8 { return nil }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        #if canImport(CoreFoundation)
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let gbkStr = String(data: data, encoding: String.Encoding(rawValue: gb18030)) {
            return gbkStr
        }
        #endif
        return String(data: data, encoding: .isoLatin1)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        var blankRun = 0
        for rawLine in unified.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                if blankRun <= 1 && !lines.isEmpty {
                    lines.append("")
                }
            } else {
                blankRun = 0
                lines.append(trimmed)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
