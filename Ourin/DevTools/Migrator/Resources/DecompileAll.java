// DecompileAll.java
// Ourin Migrator 用 Ghidra post-script.
//
// 役割:
//   analyzeHeadless の -postScript として実行され、インポート完了後のプログラムに対して
//   以下の成果物を環境変数 OURIN_ANALYSIS_OUT で指定したディレクトリへ書き出す。
//
//   出力ファイル（計画「Ghidra 解析 / 生成物」と同期）:
//     decompiled.c   : 全関数の疑似 C を結合したテキスト
//     imports.json   : 外部シンボル import 一覧（JSON 配列）
//     exports.json   : エクスポートシンボル一覧（JSON 配列）
//     strings.txt    : 定義済み文字列データ一覧
//     resources.txt  : PE リソース情報（取得可能な範囲）
//
// 注意: Ghidra の疑似 C は元ソースではない。完全自動変換は行わない（計画「注意点」）。
//
// Imports:
//   ghidra.app.script.GhidraScript
//   ghidra.program.model.listing.*
//   ghidra.program.model.symbol.*
//   ghidra.app.decompiler.*
//   ghidra.program.model.mem.*
//@category Ourin.Migrator

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.address.Address;

import java.io.File;
import java.io.PrintWriter;
import java.io.IOException;
import java.util.Iterator;

public class DecompileAll extends GhidraScript {

    private File outDir;

    @Override
    public void run() throws Exception {
        String outPath = System.getenv("OURIN_ANALYSIS_OUT");
        if (outPath == null || outPath.isEmpty()) {
            println("[DecompileAll] OURIN_ANALYSIS_OUT env not set; skipping");
            return;
        }
        outDir = new File(outPath);
        if (!outDir.exists() && !outDir.mkdirs()) {
            println("[DecompileAll] Failed to create output dir: " + outPath);
            return;
        }

        println("[DecompileAll] Program: " + currentProgram.getName());
        println("[DecompileAll] Output dir: " + outDir.getAbsolutePath());

        dumpExports();
        dumpImports();
        dumpStrings();
        dumpResources();
        dumpDecompiled();
    }

    /** exports.json: エクスポートシンボル（EXTERNAL 以外の SymbolType） */
    private void dumpExports() throws IOException {
        File f = new File(outDir, "exports.json");
        SymbolTable st = currentProgram.getSymbolTable();
        SymbolIterator it = st.getAllSymbols(true);
        StringBuilder sb = new StringBuilder();
        sb.append("[\n");
        boolean first = true;
        while (it.hasNext()) {
            Symbol s = it.next();
            // エクスポート相当: 外部から見える名前付きシンボル
            if (s.getSymbolType() == ghidra.program.model.symbol.SymbolType.FUNCTION
                    || s.getSymbolType() == ghidra.program.model.symbol.SymbolType.LABEL
                    || s.getSymbolType() == ghidra.program.model.symbol.SymbolType.DATA) {
                if (s.isExternalEntryPoint() || s.getSource() != SourceType.DEFAULT) {
                    if (!first) sb.append(",\n");
                    first = false;
                    sb.append("  {");
                    sb.append("\"name\": ").append(jsonStr(s.getName(true)));
                    sb.append(", \"address\": ").append(jsonStr(s.getAddress().toString()));
                    sb.append(", \"type\": ").append(jsonStr(s.getSymbolType().toString()));
                    sb.append(", \"source\": ").append(jsonStr(s.getSource().toString()));
                    sb.append("}");
                }
            }
        }
        sb.append("\n]\n");
        writeText(f, sb.toString());
        println("[DecompileAll] exports.json written");
    }

    /** imports.json: 外部シンボル（DLL からの import） */
    private void dumpImports() throws IOException {
        File f = new File(outDir, "imports.json");
        SymbolTable st = currentProgram.getSymbolTable();
        SymbolIterator it = st.getExternalSymbols();
        StringBuilder sb = new StringBuilder();
        sb.append("[\n");
        boolean first = true;
        while (it.hasNext()) {
            Symbol s = it.next();
            if (!first) sb.append(",\n");
            first = false;
            sb.append("  {");
            sb.append("\"name\": ").append(jsonStr(s.getName(true)));
            String parent = s.getParentNamespace() != null ? s.getParentNamespace().getName(true) : "";
            sb.append(", \"library\": ").append(jsonStr(parent));
            sb.append(", \"address\": ").append(jsonStr(s.getAddress() != null ? s.getAddress().toString() : ""));
            sb.append("}");
        }
        sb.append("\n]\n");
        writeText(f, sb.toString());
        println("[DecompileAll] imports.json written");
    }

    /** strings.txt: 定義済み文字列データ */
    private void dumpStrings() throws IOException {
        File f = new File(outDir, "strings.txt");
        StringBuilder sb = new StringBuilder();
        DataIterator it = currentProgram.getListing().getDefinedData(true);
        int count = 0;
        while (it.hasNext()) {
            Data d = it.next();
            String typeName = d.getDataType().getName().toLowerCase();
            if (typeName.contains("string") || typeName.contains("char") || typeName.contains("unicode")) {
                Object val = d.getValue();
                String s = val != null ? val.toString() : "";
                // 長すぎる文字列は先頭 200 文字に切り詰め（出力肥大化防止）
                if (s.length() > 200) s = s.substring(0, 200) + "...";
                sb.append(d.getAddress().toString()).append('\t')
                  .append(d.getLength()).append('\t')
                  .append(d.getDataType().getName()).append('\t')
                  .append(s.replace('\n', ' ').replace('\r', ' '))
                  .append('\n');
                count++;
            }
        }
        writeText(f, sb.toString());
        println("[DecompileAll] strings.txt written (" + count + " entries)");
    }

    /** resources.txt: メモリブロックからリソースっぽい領域を列挙（簡易） */
    private void dumpResources() throws IOException {
        File f = new File(outDir, "resources.txt");
        StringBuilder sb = new StringBuilder();
        Memory mem = currentProgram.getMemory();
        for (ghidra.program.model.mem.MemoryBlock block : mem.getBlocks()) {
            sb.append("Block: ").append(block.getName())
              .append(" @ ").append(block.getStart()).append('-').append(block.getEnd())
              .append(" size=").append(block.getSize())
              .append(" r=").append(block.isRead()).append(" w=").append(block.isWrite())
              .append(" x=").append(block.isExecute())
              .append(" src=").append(block.getSourceName() != null ? block.getSourceName() : "")
              .append('\n');
        }
        writeText(f, sb.toString());
        println("[DecompileAll] resources.txt written");
    }

    /** decompiled.c: 全関数の疑似 C を結合 */
    private void dumpDecompiled() throws IOException {
        File f = new File(outDir, "decompiled.c");
        DecompInterface decomp = new DecompInterface();
        try {
            DecompileOptions opts = new DecompileOptions();
            decomp.setOptions(opts);
            if (!decomp.openProgram(currentProgram)) {
                writeText(f, "/* Decompiler failed to open program: "
                    + currentProgram.getName() + " */\n");
                println("[DecompileAll] decompiler failed to open program");
                return;
            }
            StringBuilder sb = new StringBuilder();
            sb.append("/* Decompiled by Ghidra for ").append(currentProgram.getName())
              .append(" - pseudo-C, NOT original source */\n\n");

            FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
            int count = 0;
            int limit = 2000; // 出力肥大化防止の上限
            while (it.hasNext() && count < limit) {
                Function func = it.next();
                DecompileResults res = decomp.decompileFunction(func, 30, monitor);
                if (res != null && res.decompileCompleted()) {
                    String code = res.getDecompiledFunction().getC();
                    if (code != null) {
                        sb.append(code).append("\n\n");
                        count++;
                    }
                }
            }
            if (count >= limit) {
                sb.append("/* ... truncated at ").append(limit).append(" functions */\n");
            }
            writeText(f, sb.toString());
            println("[DecompileAll] decompiled.c written (" + count + " functions)");
        } finally {
            decomp.dispose();
        }
    }

    // ---- helpers ----

    private static void writeText(File f, String text) throws IOException {
        try (PrintWriter pw = new PrintWriter(f, "UTF-8")) {
            pw.print(text);
        }
    }

    private static String jsonStr(String s) {
        if (s == null) return "\"\"";
        StringBuilder sb = new StringBuilder();
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
        return sb.toString();
    }
}
