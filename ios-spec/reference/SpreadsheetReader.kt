package com.lifestyle.nestly.data.importer

import org.w3c.dom.Document
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Reads tabular exports regardless of container: CSV, TSV, XLSX (zip + XML),
 * Excel 2003 SpreadsheetML (.xls saved as XML) and HTML-table .xls files.
 * Detection is by content, not file name, since exports often carry the
 * wrong extension. Legacy binary .xls (OLE) is the one format we can't parse
 * without a heavy dependency; it gets a clear, actionable error.
 */
object SpreadsheetReader {

    fun parseRecords(input: InputStream): List<Map<String, String>> {
        val bytes = input.readBytes()
        return CsvParser.recordsFromRows(parseRows(bytes))
    }

    fun parseRows(bytes: ByteArray): List<List<String>> {
        if (bytes.isEmpty()) return emptyList()
        return when {
            isZip(bytes) -> XlsxParser.parseRows(bytes)
            isOle(bytes) -> throw IllegalArgumentException(
                "This is a legacy binary .xls file, which isn't supported. " +
                    "Open it in Excel or Google Sheets and re-export/save as .xlsx or .csv, then import that file.",
            )
            else -> {
                val text = decodeText(bytes)
                val trimmed = text.trimStart('\uFEFF', ' ', '\t', '\r', '\n')
                when {
                    trimmed.startsWith("<?xml") && trimmed.contains("Workbook") ->
                        SpreadsheetMlParser.parseRows(text)
                    trimmed.startsWith("<") && (trimmed.contains("<table", ignoreCase = true) || trimmed.contains("<tr", ignoreCase = true)) ->
                        HtmlTableParser.parseRows(text)
                    else -> {
                        val firstLine = text.lineSequence().firstOrNull().orEmpty()
                        val delimiter = if (firstLine.count { it == '\t' } > firstLine.count { it == ',' }) '\t' else ','
                        CsvParser.parse(text.reader(), delimiter)
                    }
                }
            }
        }
    }

    private fun isZip(bytes: ByteArray) =
        bytes.size >= 4 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4B.toByte() // "PK"

    private fun isOle(bytes: ByteArray) =
        bytes.size >= 4 && bytes[0] == 0xD0.toByte() && bytes[1] == 0xCF.toByte() &&
            bytes[2] == 0x11.toByte() && bytes[3] == 0xE0.toByte()

    private fun decodeText(bytes: ByteArray): String = when {
        bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte() ->
            String(bytes, Charsets.UTF_16LE)
        bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte() ->
            String(bytes, Charsets.UTF_16BE)
        else -> String(bytes, Charsets.UTF_8)
    }
}

internal fun parseXml(bytes: ByteArray): Document {
    val factory = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
        runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
        runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
    }
    return factory.newDocumentBuilder().parse(ByteArrayInputStream(bytes))
}

internal fun Element.textOfDescendants(tag: String): String {
    val nodes = getElementsByTagName(tag)
    val sb = StringBuilder()
    for (i in 0 until nodes.length) sb.append(nodes.item(i).textContent)
    return sb.toString()
}

/** Minimal XLSX reader: first worksheet + shared strings, via zip + DOM. No external deps. */
object XlsxParser {

    fun parseRows(bytes: ByteArray): List<List<String>> {
        val entries = mutableMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) entries[entry.name] = zip.readBytes()
                entry = zip.nextEntry
            }
        }

        val sharedStrings: List<String> = entries["xl/sharedStrings.xml"]?.let { xml ->
            val doc = parseXml(xml)
            val items = doc.getElementsByTagName("si")
            List(items.length) { i ->
                (items.item(i) as Element).textOfDescendants("t")
            }
        } ?: emptyList()

        val sheetXml = findFirstSheet(entries) ?: return emptyList()
        val doc = parseXml(sheetXml)
        val rowNodes = doc.getElementsByTagName("row")
        val rows = mutableListOf<List<String>>()
        for (r in 0 until rowNodes.length) {
            val rowEl = rowNodes.item(r) as Element
            val cells = rowEl.getElementsByTagName("c")
            val values = mutableMapOf<Int, String>()
            var maxCol = -1
            for (c in 0 until cells.length) {
                val cell = cells.item(c) as Element
                val col = columnIndex(cell.getAttribute("r"))
                if (col < 0) continue
                val value = cellValue(cell, sharedStrings)
                values[col] = value
                if (col > maxCol) maxCol = col
            }
            rows += List(maxCol + 1) { values[it].orEmpty() }
        }
        return rows
    }

    private fun findFirstSheet(entries: Map<String, ByteArray>): ByteArray? {
        // Resolve the first sheet through workbook relationships when present.
        val workbook = entries["xl/workbook.xml"]
        val rels = entries["xl/_rels/workbook.xml.rels"]
        if (workbook != null && rels != null) {
            runCatching {
                val wbDoc = parseXml(workbook)
                val sheets = wbDoc.getElementsByTagName("sheet")
                if (sheets.length > 0) {
                    val relId = (sheets.item(0) as Element).getAttribute("r:id")
                    val relDoc = parseXml(rels)
                    val relNodes = relDoc.getElementsByTagName("Relationship")
                    for (i in 0 until relNodes.length) {
                        val rel = relNodes.item(i) as Element
                        if (rel.getAttribute("Id") == relId) {
                            val target = rel.getAttribute("Target")
                            val path = when {
                                target.startsWith("/") -> target.trimStart('/')
                                target.startsWith("xl/") -> target
                                else -> "xl/$target"
                            }
                            entries[path]?.let { return it }
                        }
                    }
                }
            }
        }
        return entries
            .filterKeys { it.startsWith("xl/worksheets/sheet") && it.endsWith(".xml") }
            .toSortedMap()
            .values
            .firstOrNull()
    }

    private fun columnIndex(ref: String?): Int {
        if (ref.isNullOrBlank()) return -1
        var col = 0
        var seen = false
        for (ch in ref) {
            if (!ch.isLetter()) break
            seen = true
            col = col * 26 + (ch.uppercaseChar() - 'A' + 1)
        }
        return if (seen) col - 1 else -1
    }

    private fun cellValue(cell: Element, sharedStrings: List<String>): String {
        val type = cell.getAttribute("t")
        return when (type) {
            "s" -> {
                val index = cell.textOfDescendants("v").trim().toIntOrNull() ?: return ""
                sharedStrings.getOrNull(index).orEmpty()
            }
            "inlineStr" -> cell.textOfDescendants("t")
            else -> cell.textOfDescendants("v")
        }
    }
}

/** Excel 2003 XML Spreadsheet (.xls saved as XML). */
object SpreadsheetMlParser {
    fun parseRows(text: String): List<List<String>> {
        val doc = parseXml(text.toByteArray(Charsets.UTF_8))
        val rowNodes = doc.getElementsByTagNameNS("*", "Row")
        val rows = mutableListOf<List<String>>()
        for (r in 0 until rowNodes.length) {
            val cells = (rowNodes.item(r) as Element).getElementsByTagNameNS("*", "Cell")
            rows += List(cells.length) { i ->
                val cell = cells.item(i) as Element
                cell.getElementsByTagNameNS("*", "Data").let {
                    if (it.length > 0) it.item(0).textContent else ""
                }
            }
        }
        return rows
    }
}

/** .xls files that are really an HTML table (a common export trick). */
object HtmlTableParser {
    private val rowRegex = Regex("<tr[^>]*>(.*?)</tr>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val cellRegex = Regex("<t[dh][^>]*>(.*?)</t[dh]>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val tagRegex = Regex("<[^>]+>")

    fun parseRows(text: String): List<List<String>> =
        rowRegex.findAll(text).map { row ->
            cellRegex.findAll(row.groupValues[1]).map { cell ->
                unescape(cell.groupValues[1].replace(tagRegex, "")).trim()
            }.toList()
        }.toList()

    private fun unescape(value: String): String = value
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
}
