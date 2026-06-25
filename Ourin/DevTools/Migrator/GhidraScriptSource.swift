import Foundation

/// Ghidra post-script `DecompileAll.java` のソース文字列。
///
/// `Resources/DecompileAll.java` は開発/編集用の参照ファイル。
/// バンドル同梱を前提とせず、本文字列から一時ファイルとして実体化する（参考: 計画「Ghidra は Ourin に同梱しない」）。
/// 本文字列が実行時の権威ソース。`.java` を編集した場合はこちらも同期すること。
enum GhidraScriptSource {
    static let decompileAll = #"""
// DecompileAll.java - materialized by Ourin Migrator at runtime.
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

import java.io.File;
import java.io.PrintWriter;
import java.io.IOException;

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

    private void dumpExports() throws IOException {
        File f = new File(outDir, "exports.json");
        SymbolTable st = currentProgram.getSymbolTable();
        SymbolIterator it = st.getAllSymbols(true);
        StringBuilder sb = new StringBuilder();
        sb.append("[\n");
        boolean first = true;
        while (it.hasNext()) {
            Symbol s = it.next();
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
            int limit = 2000;
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
"""#
}
