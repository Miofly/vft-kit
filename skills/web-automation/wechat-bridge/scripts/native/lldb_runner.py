"""LLDB-only entry point: evaluate once on the main thread, always detach."""
import json
from pathlib import Path


def run(config_path):
    import lldb
    config = json.loads(Path(config_path).read_text())
    result = {'ok': False, 'detached': False}
    process = None
    try:
        debugger = lldb.debugger
        debugger.SetAsync(False)
        target = debugger.CreateTarget('')
        error = lldb.SBError()
        process = target.AttachToProcessWithID(debugger.GetListener(), config['pid'], error)
        if error.Fail() or not process.IsValid():
            raise RuntimeError('attach refused')
        mains = [t for t in process if t.GetQueueName() == 'com.apple.main-thread']
        if len(mains) != 1:
            raise RuntimeError('main thread not unique')
        process.SetSelectedThread(mains[0])
        signals = process.GetUnixSignals()
        stop_signal = signals.GetSignalNumberFromName('SIGSTOP')
        signals.SetShouldStop(stop_signal, False)
        signals.SetShouldNotify(stop_signal, False)
        signals.SetShouldSuppress(stop_signal, True)
        options = lldb.SBExpressionOptions()
        options.SetLanguage(lldb.eLanguageTypeC_plus_plus)
        options.SetTimeoutInMicroSeconds(5000000)
        options.SetTryAllThreads(False)
        options.SetUnwindOnError(True)
        value = mains[0].GetFrameAtIndex(0).EvaluateExpression(
            Path(config['expression']).read_text(), options)
        if value.GetError().Fail():
            raise RuntimeError('expression failed')
        result.update(ok=True, value=value.GetValueAsSigned(-999))
    except Exception as error:
        result['error'] = type(error).__name__
    finally:
        if process is not None and process.IsValid():
            result['detached'] = process.Detach().Success()
        Path(config['output']).write_text(json.dumps(result))
