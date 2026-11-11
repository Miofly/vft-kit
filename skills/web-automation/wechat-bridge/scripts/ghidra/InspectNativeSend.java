// Focused inspection on the existing project; no full auto-analysis.
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
public class InspectNativeSend extends GhidraScript {
  public void run() throws Exception {
    for(String arg:getScriptArgs()) {
      long address=Long.parseLong(arg.replace("0x",""),16);
      var at=toAddr(address);
      disassemble(at);
      Function fn=getFunctionAt(at);
      if(fn==null) fn=createFunction(at,null);
      if(fn==null) { println("NO_FUNCTION "+arg); continue; }
      DecompInterface decomp=new DecompInterface();
      try {
        decomp.openProgram(currentProgram);
        var result=decomp.decompileFunction(fn,45,monitor);
        if(result.decompileCompleted()) {
          String text=result.getDecompiledFunction().getC();
          println("NATIVE_FUNCTION "+arg+"\n"+text);
        } else println("DECOMPILE_FAILED "+arg+" "+result.getErrorMessage());
      } finally {decomp.dispose();}
    }
  }
}
