import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
public class DumpMeta extends GhidraScript {
  Memory mem;
  String lps(long vm){ try{ Address a=toAddr(vm); int n=mem.getByte(a)&0xff; if(n<1||n>120) return null;
      byte[] b=new byte[n]; mem.getBytes(a.add(1),b); String s=new String(b,"US-ASCII");
      for(char c: s.toCharArray()) if(c<32||c>126) return null; return s; }catch(Exception e){return null;} }
  void dump(long base){
    println("=== struct " + Long.toHexString(base));
    for(int i=0;i<8;i++){ try{ long v=mem.getLong(toAddr(base+i*8)); println("  +0x" + Integer.toHexString(i*8) + " = " + Long.toHexString(v)); }catch(Exception e){} }
    try{
      long sd=mem.getLong(toAddr(base+8));
      long dt=mem.getLong(toAddr(base+16));
      int off=mem.getInt(toAddr(dt+4));
      println("  stringdata=" + Long.toHexString(sd) + " data=" + Long.toHexString(dt) + " classNameOff=" + off);
      println("  className@sd+off = " + lps(sd+off));
      println("  at sd+0: len=" + (mem.getByte(toAddr(sd))&0xff) + " s0=" + lps(sd));
      StringBuilder u=new StringBuilder(); for(int i=0;i<10;i++){ u.append(Integer.toHexString(mem.getInt(toAddr(dt+i*4)))).append(","); }
      println("  data[]=" + u);
    }catch(Exception e){ println("  decode-fail " + e); }
  }
  public void run() throws Exception {
    mem=currentProgram.getMemory();
    for(String a : getScriptArgs()) dump(Long.parseLong(a.replace("0x",""),16));
  }
}
