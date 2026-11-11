import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import java.util.*;
public class EnumMeta extends GhidraScript {
  Memory mem; List<long[]> ex=new ArrayList<>(), rd=new ArrayList<>();
  boolean inEx(long v){for(long[]r:ex) if(v>=r[0]&&v<r[1])return true;return false;}
  boolean inRd(long v){for(long[]r:rd) if(v>=r[0]&&v<r[1])return true;return false;}
  public void run() throws Exception {
    mem=currentProgram.getMemory();
    for(MemoryBlock mb:mem.getBlocks()){ if(!mb.isInitialized())continue;
      long s=mb.getStart().getOffset(),e=mb.getEnd().getOffset();
      if(mb.isExecute())ex.add(new long[]{s,e}); else if(mb.isRead())rd.add(new long[]{s,e}); }
    int n=0;
    for(MemoryBlock mb:mem.getBlocks()){
      if(!mb.isInitialized()||mb.isExecute())continue;
      long s=mb.getStart().getOffset(),e=mb.getEnd().getOffset();
      for(long o=s;o+48<=e;o+=8){
        long sup,sd,dt,smc;
        try{ sup=mem.getLong(toAddr(o)); sd=mem.getLong(toAddr(o+8)); dt=mem.getLong(toAddr(o+16)); smc=mem.getLong(toAddr(o+24)); }
        catch(Exception x){continue;}
        if(smc<0x1000||!inEx(smc))continue;
        if(!inRd(sd)||!inRd(dt))continue;
        int rev,noff;
        try{ rev=mem.getInt(toAddr(dt)); noff=mem.getInt(toAddr(dt+4)); }catch(Exception x){continue;}
        if(rev<7||rev>12||noff!=0)continue;
        int sz,off;
        try{ sz=mem.getInt(toAddr(sd+4)); off=mem.getInt(toAddr(sd+16)); }catch(Exception x){continue;}
        if(sz<1||sz>80)continue;
        StringBuilder sb=new StringBuilder();
        try{ Address a=toAddr(sd+off); for(int i=0;i<sz;i++){ byte c=mem.getByte(a.add(i)); if(c<32||c>126){sb=null;break;} sb.append((char)c);} }
        catch(Exception x){sb=null;}
        if(sb==null)continue;
        String nm=sb.toString();
        if(!nm.matches("[A-Za-z_][A-Za-z0-9_:<>]*"))continue;
        n++;
        if(n<=3000) println("META "+Long.toHexString(o)+" name="+nm+" smc="+Long.toHexString(smc)+" sup="+Long.toHexString(sup));
      }
    }
    println("META-TOTAL "+n);
  }
}
