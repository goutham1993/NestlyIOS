package com.lifestyle.nestly.data.importer

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.StringReader

class CsvParserTest {
    @Test
    fun parsesQuotedFieldsEmptyFieldsAndEscapedQuotes() {
        val rows = CsvParser.parse(StringReader("\"a\",,\"say \"\"hi\"\"\",3\n"))
        assertEquals(listOf(listOf("a", "", "say \"hi\"", "3")), rows)
    }

    @Test
    fun keepsNewlinesInsideQuotedFields() {
        val rows = CsvParser.parse(StringReader("\"Type\",\"Note\"\r\n\"Pump\",\"line one \nline two\"\r\n"))
        assertEquals(2, rows.size)
        assertEquals("line one \nline two", rows[1][1])
    }

    @Test
    fun parseRecordsDropsBlankValuesAndBom() {
        val records = CsvParser.parseRecords(StringReader("\uFEFF\"Type\",\"Note\"\n\"Diaper\",\n"))
        assertEquals(listOf(mapOf("Type" to "Diaper")), records)
    }
}
