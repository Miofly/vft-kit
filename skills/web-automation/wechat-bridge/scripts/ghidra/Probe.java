import ghidra.app.script.GhidraScript;
public class Probe extends GhidraScript {
  public void run() throws Exception {
    println("FUNCS " + currentProgram.getFunctionManager().getFunctionCount());
    println("SYMS " + currentProgram.getSymbolTable().getNumSymbols());
    println("LANG " + currentProgram.getLanguageID());
    int n=0; for (var f : currentProgram.getFunctionManager().getFunctions(true)) {
      if(n<8) println("FN " + f.getEntryPoint() + " " + f.getName());
      n++; }
  }
}
