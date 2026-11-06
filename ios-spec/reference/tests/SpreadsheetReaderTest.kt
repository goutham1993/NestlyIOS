package com.lifestyle.nestly.data.importer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class SpreadsheetReaderTest {

    private fun xlsxBytes(): ByteArray {
        val sheet = """<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1">
<c r="A1" t="inlineStr"><is><t>Type</t></is></c>
<c r="B1" t="inlineStr"><is><t>Profile Name</t></is></c>
<c r="C1" t="inlineStr"><is><t>Start Date/time (Epoch)</t></is></c>
<c r="D1" t="inlineStr"><is><t>[Bottle Feed] Type</t></is></c>
<c r="E1" t="inlineStr"><is><t>[Bottle Feed] Volume</t></is></c>
<c r="F1" t="inlineStr"><is><t>_familyKey</t></is></c>
<c r="G1" t="inlineStr"><is><t>_profileKey</t></is></c>
<c r="H1" t="inlineStr"><is><t>_activityKey</t></is></c>
</row>
<row r="2">
<c r="A2" t="inlineStr"><is><t>Bottle Feed</t></is></c>
<c r="B2" t="inlineStr"><is><t>Rithan</t></is></c>
<c r="C2"><v>1790896458000</v></c>
<c r="D2" t="inlineStr"><is><t>Breast Milk</t></is></c>
<c r="E2"><v>150</v></c>
<c r="F2" t="inlineStr"><is><t>fam-1</t></is></c>
<c r="G2" t="inlineStr"><is><t>prof-1</t></is></c>
<c r="H2" t="inlineStr"><is><t>act-1</t></is></c>
</row>
</sheetData></worksheet>"""
        val workbook = """<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"""
        val rels = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"""
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            fun put(name: String, content: String) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(content.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }
            put("xl/workbook.xml", workbook)
            put("xl/_rels/workbook.xml.rels", rels)
            put("xl/worksheets/sheet1.xml", sheet)
        }
        return out.toByteArray()
    }

    @Test
    fun readsXlsxIntoRecords() {
        val records = SpreadsheetReader.parseRecords(ByteArrayInputStream(xlsxBytes()))
        assertEquals(1, records.size)
        assertEquals("Bottle Feed", records[0]["Type"])
        assertEquals("1790896458000", records[0]["Start Date/time (Epoch)"])
    }

    @Test
    fun xlsxBottleRowMapsToNaraRecord() {
        val records = SpreadsheetReader.parseRecords(ByteArrayInputStream(xlsxBytes()))
        val activity = records.mapNotNull(NaraRowMapper::map).single() as NaraRecord.Activity
        assertEquals(1790896458000L, activity.startTime)
        assertEquals(150.0, activity.bottle!!.totalMl!!, 0.0)
    }

    @Test
    fun sharedStringsResolve() {
        val sheet = """<?xml version="1.0"?><worksheet><sheetData>
<row><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
<row><c r="A2" t="s"><v>2</v></c><c r="B2"><v>42</v></c></row>
</sheetData></worksheet>"""
        val shared = """<?xml version="1.0"?><sst><si><t>Type</t></si><si><t>Name</t></si><si><t>Diaper</t></si></sst>"""
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            zip.putNextEntry(ZipEntry("xl/sharedStrings.xml")); zip.write(shared.toByteArray()); zip.closeEntry()
            zip.putNextEntry(ZipEntry("xl/worksheets/sheet1.xml")); zip.write(sheet.toByteArray()); zip.closeEntry()
        }
        val records = SpreadsheetReader.parseRecords(ByteArrayInputStream(out.toByteArray()))
        assertEquals(mapOf("Type" to "Diaper", "Name" to "42"), records.single())
    }

    @Test
    fun readsTsvAndHtmlAndCsv() {
        val tsv = "Type\tProfile Name\nDiaper\tRithan\n"
        assertEquals("Diaper", SpreadsheetReader.parseRecords(ByteArrayInputStream(tsv.toByteArray()))[0]["Type"])

        val html = "<html><table><tr><td>Type</td><td>Profile Name</td></tr><tr><td>Diaper</td><td>Rithan</td></tr></table></html>"
        assertEquals("Rithan", SpreadsheetReader.parseRecords(ByteArrayInputStream(html.toByteArray()))[0]["Profile Name"])

        val csv = "Type,Profile Name\nDiaper,Rithan\n"
        assertEquals("Diaper", SpreadsheetReader.parseRecords(ByteArrayInputStream(csv.toByteArray()))[0]["Type"])
    }

    @Test
    fun legacyBinaryXlsGetsActionableError() {
        val ole = byteArrayOf(0xD0.toByte(), 0xCF.toByte(), 0x11.toByte(), 0xE0.toByte(), 0, 0, 0, 0)
        try {
            SpreadsheetReader.parseRecords(ByteArrayInputStream(ole))
            fail("expected error")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains(".xlsx or .csv"))
        }
    }

    @Test
    fun flexibleLongParsing() {
        assertEquals(1790896458000L, "1790896458000".toLongFlexible())
        assertEquals(1790896458000L, "1790896458000.0".toLongFlexible())
        assertEquals(3600L, "3600.0".toLongFlexible())
    }
}
