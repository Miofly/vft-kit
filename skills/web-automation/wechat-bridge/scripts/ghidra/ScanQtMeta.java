// Find Qt6 QMetaObject structs now that chained fixups are resolved.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import java.util.*;

public class ScanQtMeta extends GhidraScript {
  Memory mem; List<long[]> exec = new ArrayList<>(); List<long[]> rd = new ArrayList<>();

  boolean inExec(long v){ for(long[]r:exec) if(v>=r[0]&&v<r[1]) return true; return false; }
  boolean inRd(long v){ for(long[]r:rd) if(v>=r[0]&&v<r[1]) return true; return false; }

  String lps(long vm){ try{ Address a=toAddr(vm); int n=mem.getByte(a)&0xff; if(n<1||n>120) return null;
      byte[] b=new byte[n]; mem.getBytes(a.add(1),b); String s=new String(b,"US-ASCII");
      for(char c: s.toCharArray()) if(c<32||c>126) return null; return s; }catch(Exception e){return null;} }
  String nts(long vm){ try{ StringBuilder sb=new StringBuilder(); Address a=toAddr(vm);
      for(int i=0;i<120;i++){ byte c=mem.getByte(a.add(i)); if(c==0) break; if(c<32||c>126) return null; sb.append((char)c);} 
      return sb.length()>1?sb.toString():null;}catch(Exception e){return null;} }

  public void run() throws Exception {
    mem = currentProgram.getMemory();
    for (MemoryBlock mb : mem.getBlocks()) {
      if(!mb.isInitialized()) continue;
      long s=mb.getStart().getOffset(), e=mb.getEnd().getOffset();
      if(mb.isExecute()) exec.add(new long[]{s,e});
      if(mb.isRead()&&!mb.isExecute()) rd.add(new long[]{s,e});
    }
    println("EXEC-BLOCKS " + exec.size() + " RD-BLOCKS " + rd.size());
    int n=0;
    for (MemoryBlock mb : mem.getBlocks()) {
      if(!mb.isInitialized()||mb.isExecute()) continue;
      long s=mb.getStart().getOffset(), e=mb.getEnd().getOffset();
      for (long o=s; o+32<=e; o+=8) {
        long v1,v2,v3;
        try { v1=mem.getLong(toAddr(o+8)); v2=mem.getLong(toAddr(o+16)); v3=mem.getLong(toAddr(o+24)); }
        catch(Exception ex){ continue; }
        if(!inRd(v1)) continue;
        if(!inRd(v2)) continue;
        if(v3<0x1000||!inExec(v3)) continue;
        String cls=null;
        try { int off=mem.getInt(toAddr(v2+4)); cls=lps(v1+off); if(cls==null) cls=nts(v1+off); } catch(Exception ex){}
        if(cls!=null && cls.length()>1){
          if(n<400) println("META struct=" + Long.toHexString(o-8) + " sd=" + Long.toHexString(v1)
             + " data=" + Long.toHexString(v2) + " smc=" + Long.toHexString(v3) + " class=" + cls);
          n++;
        }
      }
      if(monitor.isCancelled()) return;
    }
    println("META-TOTAL " + n);
  }
}
