import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
public class WalkMeta extends GhidraScript {
  Memory mem;
  String asc(long vm,int max){ try{ StringBuilder sb=new StringBuilder(); Address a=toAddr(vm);
     for(int i=0;i<max;i++){ byte c=mem.getByte(a.add(i)); if(c==0) break; if(c<32||c>126) return null; sb.append((char)c);} return sb.toString(); }catch(Exception e){return null;} }
  public void run() throws Exception {
    mem=currentProgram.getMemory();
    long base=Long.parseLong(getScriptArgs()[0].replace("0x",""),16);
    for(int lvl=0; lvl<8 && base!=0; lvl++){
      long sup=mem.getLong(toAddr(base));
      long sd =mem.getLong(toAddr(base+8));
      long dt =mem.getLong(toAddr(base+16));
      long smc=mem.getLong(toAddr(base+24));
      long rel=mem.getLong(toAddr(base+32));
      int rev=0,noff=0; try{ rev=mem.getInt(toAddr(dt)); noff=mem.getInt(toAddr(dt+4)); }catch(Exception e){}
      String n1=asc(sd+noff,64), n2=asc(sd,64);
      println("LVL"+lvl+" base="+Long.toHexString(base)+" sup="+Long.toHexString(sup)
        +" sd="+Long.toHexString(sd)+" data="+Long.toHexString(dt)+" smc="+Long.toHexString(smc)
        +" rev="+rev+" nameOff="+noff+" name@sd+off="+n1+" name@sd="+n2);
      base=sup;
    }
  }
}
