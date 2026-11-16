import ghidra.app.script.GhidraScript;
import ghidra.program.model.mem.Memory;
public class MetaNames extends GhidraScript {
  public void run() throws Exception {
    Memory mem=currentProgram.getMemory();
    long mo=Long.parseLong(getScriptArgs()[0].replace("0x",""),16);
    long sd=mem.getLong(toAddr(mo+8)), dt=mem.getLong(toAddr(mo+16));
    int mc=mem.getInt(toAddr(dt+16)), mo_=mem.getInt(toAddr(dt+20));
    // collect declared sizes (field +4 of each 24-byte entry) and table end
    int NE=200; int tableEnd=0;
    java.util.List<Integer> sizes=new java.util.ArrayList<>();
    for(int i=0;i<NE;i++){
      int sz=mem.getInt(toAddr(sd+i*24+4));
      if(sz<0||sz>200) break;
      sizes.add(sz);
      if(sz>0) tableEnd+=sz;
    }
    println("ENTRIES="+sizes.size()+" sizes="+sizes);
    // scan the blob for printable runs and match by size order
    java.util.List<String> found=new java.util.ArrayList<>();
    for(long o=sd; o<sd+4096 && found.size()<sizes.size(); o++){
      int sz=sizes.get(found.size());
      if(sz==0){ found.add(""); continue; }
      StringBuilder b=new StringBuilder(); boolean ok=true;
      for(int i=0;i<sz;i++){ byte c=mem.getByte(toAddr(o+i)); if(c<32||c>126){ok=false;break;} b.append((char)c); }
      if(ok){ byte nx=mem.getByte(toAddr(o+sz)); if(nx==0){ found.add(b.toString()); o+=sz; } }
    }
    println("NAMES="+found);
    for(int i=0;i<mc;i++){
      int b=mo_+i*5;
      int nmIdx=mem.getInt(toAddr(dt+b*4)), argc=mem.getInt(toAddr(dt+(b+1)*4)), flags=mem.getInt(toAddr(dt+(b+4)*4));
      String nm=nmIdx>=0&&nmIdx<found.size()?found.get(nmIdx):"<idx"+nmIdx+">";
      println("  m["+i+"] "+nm+" argc="+argc+" flags=0x"+Integer.toHexString(flags));
    }
  }
}
