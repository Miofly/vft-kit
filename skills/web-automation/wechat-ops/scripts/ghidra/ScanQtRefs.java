// Locate data references to the Qt moc string region. Prints BLOCK/STR/REF lines.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import java.util.*;

public class ScanQtRefs extends GhidraScript {
  public void run() throws Exception {
    Memory mem = currentProgram.getMemory();
    String[] pats = {"QTextEditControl", "QTextEditPrivate", "QTextEditMimeData", "QMetaObject"};
    List<Address> hits = new ArrayList<>();
    for (String p : pats) {
      Address a = mem.getMinAddress();
      byte[] b = p.getBytes("US-ASCII");
      while ((a = mem.findBytes(a, b, null, true, monitor)) != null) {
        hits.add(a);
        println("STR " + p + " @ " + a);
        a = a.add(1);
      }
    }
    if (hits.isEmpty()) { println("NO-HITS"); return; }
    long lo = Long.MAX_VALUE, hi = 0;
    for (Address a : hits) { long o = a.getOffset(); lo = Math.min(lo, o); hi = Math.max(hi, o); }
    lo -= 0x40000; hi += 0x4000;
    println("REGION " + Long.toHexString(lo) + " - " + Long.toHexString(hi));
    int n = 0;
    for (MemoryBlock mb : mem.getBlocks()) {
      if (!mb.isInitialized()) continue;
      long s = mb.getStart().getOffset(), e = mb.getEnd().getOffset();
      println("BLOCK " + mb.getName() + " " + Long.toHexString(s) + "-" + Long.toHexString(e)
              + (mb.isExecute() ? " X" : "") + (mb.isRead() ? " R" : "") + (mb.isWrite() ? " W" : ""));
      for (long o = s; o + 8 <= e; o += 8) {
        long v;
        try { v = mem.getLong(toAddr(o)); } catch (Exception ex) { continue; }
        if (v >= lo && v < hi) {
          if (n < 600) println("REF entry=" + Long.toHexString(o) + " -> " + Long.toHexString(v));
          n++;
        }
      }
      if (monitor.isCancelled()) return;
    }
    println("TOTAL-REFS " + n);
  }
}
