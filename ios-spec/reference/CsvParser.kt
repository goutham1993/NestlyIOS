package com.lifestyle.nestly.data.importer

import java.io.Reader

/** Minimal RFC 4180 parser: quoted fields, escaped quotes (`""`), and newlines inside quotes. */
object CsvParser {
    fun parse(reader: Reader, delimiter: Char = ','): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        var fieldStarted = false

        fun endField() {
            row.add(field.toString())
            field.setLength(0)
            fieldStarted = false
        }

        fun endRow() {
            endField()
            if (!(row.size == 1 && row[0].isEmpty())) rows.add(row)
            row = mutableListOf()
        }

        val text = reader.readText().removePrefix("\uFEFF")
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < text.length && text[i + 1] == '"') {
                        field.append('"')
                        i++
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                when (c) {
                    '"' -> if (!fieldStarted && field.isEmpty()) inQuotes = true else field.append(c)
                    delimiter -> endField()
                    '\r' -> if (i + 1 < text.length && text[i + 1] == '\n') {
                        i++
                        endRow()
                    } else {
                        endRow()
                    }
                    '\n' -> endRow()
                    else -> {
                        field.append(c)
                        fieldStarted = true
                    }
                }
            }
            i++
        }
        if (field.isNotEmpty() || row.isNotEmpty()) endRow()
        return rows
    }

    /** Parses with the first row as header; each record maps header name to value (blank values dropped). */
    fun parseRecords(reader: Reader, delimiter: Char = ','): List<Map<String, String>> =
        recordsFromRows(parse(reader, delimiter))

    /** Header-mapped records from already-parsed rows (CSV, TSV, spreadsheet, …). */
    fun recordsFromRows(rows: List<List<String>>): List<Map<String, String>> {
        if (rows.isEmpty()) return emptyList()
        val header = rows.first().map { it.trim() }
        return rows.drop(1)
            .filter { row -> row.any { it.isNotBlank() } }
            .map { values ->
                buildMap {
                    header.forEachIndexed { index, name ->
                        val value = values.getOrNull(index)
                        if (name.isNotEmpty() && !value.isNullOrBlank()) put(name, value.trim())
                    }
                }
            }
    }
}
