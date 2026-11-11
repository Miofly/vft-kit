// Emit a JSON profile (RVAs) for the chat-send classes, from the loaded Qt metaobjects.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import java.util.*;
public class Profile extends GhidraScript {
  Memory mem; List<long[]> ex=new ArrayList<>(), rd=new ArrayList<>();
  long u32(long a) throws Exception { return mem.getInt(toAddr(a))&0xffffffffL; }
  boolean isMetaObjectFn(long fn,long meta) throws Exception {
    for(long pc=fn; pc<fn+0x30; pc+=4){
      long w1,w2;
      try{ w1=u32(pc); w2=u32(pc+4); }catch(Exception e){ return false; }
      if((w1&0x9f000000L)!=0x90000000L) continue;
      if((w2&0xff800000L)!=0x91000000L) continue;
      long rd1=w1&0x1f, rd2=w2&0x1f, rn2=(w2>>5)&0x1f;
      if(rd1!=rd2||rn2!=rd1) continue;
      long imm21=((w1>>5)&0x7ffffL)<<2 | ((w1>>29)&0x3);
      long page=(pc&~0xfffL)+(imm21<<12);
      if(page+((w2>>10)&0xfffL)==meta) return true;
    }
    return false;
  }
  boolean inEx(long v){for(long[]r:ex) if(v>=r[0]&&v<r[1])return true;return false;}
  boolean inRd(long v){for(long[]r:rd) if(v>=r[0]&&v<r[1])return true;return false;}
  // A class can have several vtables (multiple inheritance). Return all slots
  // whose 0th entry is the class's metaObject(): an object is an instance of the
  // class if its vptr matches ANY of them. Primary first (offset-to-top == 0).
  List<Long> findVtables(long meta) throws Exception {
    List<Long> primary=new ArrayList<>(), rest=new ArrayList<>();
    for(MemoryBlock mb:mem.getBlocks()){
      if(!mb.isInitialized()||mb.isExecute()) continue;
      long s=mb.getStart().getOffset(), en=mb.getEnd().getOffset();
      for(long o=s;o+8<=en;o+=8){
        long v;
        try{ v=mem.getLong(toAddr(o)); }catch(Exception e){ continue; }
        if(!inEx(v)) continue;
        if(!isMetaObjectFn(v,meta)) continue;
        boolean isPrimary=false;
        try{ isPrimary = o>=16 && mem.getLong(toAddr(o-16))==0; }catch(Exception e){}
        (isPrimary?primary:rest).add(o);
      }
    }
    List<Long> all=new ArrayList<>(primary); all.addAll(rest);
    return all;
  }
  String nameAt(long sd,int idx) throws Exception {
    // This build uses Qt5-style QByteArrayData entries. offset is relative to
    // the start of each 24-byte header, not sd and not the offset field itself.
    if(idx<0||idx>4096) return null;
    long entry=sd+(long)idx*24;
    int size=mem.getInt(toAddr(entry+4));
    long offset=mem.getLong(toAddr(entry+16));
    if(size<0||size>512||offset<-1048576||offset>1048576) return null;
    long chars=entry+offset;
    StringBuilder text=new StringBuilder();
    for(int i=0;i<size;i++){
      int c=mem.getByte(toAddr(chars+i))&0xff;
      if(c<32||c>126) return null;
      text.append((char)c);
    }
    return mem.getByte(toAddr(chars+size))==0?text.toString():null;
  }
  public void run() throws Exception {
    mem=currentProgram.getMemory();
    for(MemoryBlock mb:mem.getBlocks()){ if(!mb.isInitialized())continue;
      long s=mb.getStart().getOffset(),e=mb.getEnd().getOffset();
      if(mb.isExecute())ex.add(new long[]{s,e}); else if(mb.isRead())rd.add(new long[]{s,e}); }
    String[] want={"mmui::XTextEdit","mmui::ChatInputField","mmui::ChatInputView","mmui::ChatInputSendView","QTextEdit"};
    Map<String,long[]> hits=new LinkedHashMap<>();
    for(MemoryBlock mb:mem.getBlocks()){
      if(!mb.isInitialized()||mb.isExecute())continue;
      long s=mb.getStart().getOffset(),e=mb.getEnd().getOffset();
      for(long o=s;o+48<=e;o+=8){
        long sd,dt,smc;
        try{ sd=mem.getLong(toAddr(o+8)); dt=mem.getLong(toAddr(o+16)); smc=mem.getLong(toAddr(o+24)); }catch(Exception x){continue;}
        if(smc<0x1000||!inEx(smc)||!inRd(sd)||!inRd(dt))continue;
        int rev,noff; try{ rev=mem.getInt(toAddr(dt)); noff=mem.getInt(toAddr(dt+4)); }catch(Exception x){continue;}
        if(rev<7||rev>12||noff!=0)continue;
        String nm=nameAt(sd,0); if(nm==null)continue;
        for(String w:want) if(w.equals(nm)) hits.put(nm,new long[]{o,sd,dt,smc});
      }
    }
    println("{");
    println("  \"classes\": {");
    int i=0;
    for(Map.Entry<String,long[]> en:hits.entrySet()){
      long[] v=en.getValue();
      String sup=nameAt(v[1], 0); // placeholder
      List<Long> vts=findVtables(v[0]);
      StringBuilder vtj=new StringBuilder("[");
      for(int k=0;k<vts.size();k++){ if(k>0) vtj.append(", "); vtj.append("\"0x").append(Long.toHexString(vts.get(k))).append("\""); }
      vtj.append("]");
      println("    \""+en.getKey()+"\": {\"metaobject\": \""+Long.toHexString(v[0])+"\", \"stringdata\": \""+Long.toHexString(v[1])
        +"\", \"data\": \""+Long.toHexString(v[2])+"\", \"static_metacall\": \""+Long.toHexString(v[3])
        +"\", \"vtables\": "+vtj+"}"+(++i<hits.size()?",":""));
      // Emit local method ids from this build, not a hard-coded previous map.
      int count=mem.getInt(toAddr(v[2]+16)), start=mem.getInt(toAddr(v[2]+20));
      if(count<0||count>1024||start<0) throw new IllegalStateException("Invalid method table");
      for(int m=0;m<count;m++){
        long entry=v[2]+(start+(long)m*5)*4;
        String method=nameAt(v[1],mem.getInt(toAddr(entry)));
        int argc=mem.getInt(toAddr(entry+4));
        if(method==null||!method.matches("[A-Za-z_][A-Za-z_0-9]*")||argc<0||argc>64)
          throw new IllegalStateException("Unresolved method: "+en.getKey()+" #"+m);
        println("METHOD "+en.getKey()+" "+m+" "+method+" "+argc);
      }
    }
    println("  }");
    println("}");
  }
}
