import fs from "node:fs/promises";
import { Workbook } from "@oai/artifact-tool";

const outputDir = "E:/FPGA drive/tmp/reintegration_audit_20261019";
const csvPath = "E:/FPGA drive/HDMI_DDR3_OV5640/docs/reintegration/function_matrix.csv";
const workbook = await Workbook.fromCSV(await fs.readFile(csvPath, "utf8"), {
  sheetName: "功能矩阵",
});
const sheet = workbook.worksheets.getItemAt(0);
const values = sheet.getUsedRange().values;
if (values.length !== 37 || values.some((row) => row.length !== 18)) {
  throw new Error("Unexpected matrix dimensions");
}
if (new Set(values.slice(1).map((row) => row[0])).size !== 36) {
  throw new Error("Duplicate function IDs");
}
if (values.some((row) => row.some((value) => typeof value !== "string" || !value.trim()))) {
  throw new Error("Missing or non-text audit field");
}
sheet.showGridLines = false;
sheet.getRange("A1:R37").format.font = { name: "Microsoft YaHei", size: 11 };
sheet.getRange("A1:R37").format.wrapText = true;
sheet.getRange("A1:R37").format.verticalAlignment = "top";
sheet.getRange("A1:R1").format = {
  fill: "#25362E",
  font: { name: "Microsoft YaHei", size: 11, bold: true, color: "#FFFFFF" },
  wrapText: true,
  verticalAlignment: "center",
};
const widths = [70, 250, 660, 370, 310, 310, 290, 280, 340, 350, 310, 350, 370, 110, 360, 400, 400, 300];
widths.forEach((width, column) => {
  sheet.getRangeByIndexes(0, column, 37, 1).format.columnWidthPx = width;
});
sheet.getRange("A1:R37").format.autofitRows();
sheet.freezePanes.freezeRows(1);
sheet.freezePanes.freezeColumns(2);
workbook.recalculate();
console.log((await workbook.inspect({
  kind: "table",
  range: "功能矩阵!A1:B37",
  include: "values,formulas",
  tableMaxRows: 37,
  tableMaxCols: 2,
  maxChars: 4500,
})).ndjson);
console.log((await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 10 },
  maxChars: 1000,
})).ndjson);
for (const [name, range] of [
  ["matrix_functions", "A1:B37"],
  ["matrix_evidence_sample", "C1:H4"],
  ["matrix_status_sample", "I1:R4"],
]) {
  const preview = await workbook.render({
    sheetName: "功能矩阵",
    range,
    scale: 1.5,
    format: "png",
  });
  await fs.writeFile(`${outputDir}/${name}.png`, new Uint8Array(await preview.arrayBuffer()));
}
await fs.writeFile(`${outputDir}/matrix_values.json`, JSON.stringify(values, null, 2), "utf8");
console.log(JSON.stringify({ rows: values.length - 1, columns: values[0].length, outputDir }));
