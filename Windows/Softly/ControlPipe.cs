using System.IO;
using System.IO.Pipes;
using System.Windows.Threading;

namespace Softly;

/// <summary>
/// Local control channel on the named pipe "softly-control": one line in,
/// one line out. Used by scripts and tests (preview, state, open, quit).
/// </summary>
public sealed class ControlPipe : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly Func<string, Task<string>> handle;
    private readonly CancellationTokenSource stop = new();

    public ControlPipe(Dispatcher dispatcher, Func<string, Task<string>> handle)
    {
        this.dispatcher = dispatcher;
        this.handle = handle;
    }

    public void Start() => _ = Task.Run(ServeAsync);

    private async Task ServeAsync()
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                using var server = new NamedPipeServerStream("softly-control", PipeDirection.InOut, 1,
                    PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await server.WaitForConnectionAsync(stop.Token);
                using var reader = new StreamReader(server);
                using var writer = new StreamWriter(server) { AutoFlush = true };
                var line = (await reader.ReadLineAsync())?.Trim() ?? "";
                string reply;
                try
                {
                    reply = await await dispatcher.InvokeAsync(() => handle(line));
                }
                catch (Exception e)
                {
                    reply = "error: " + e.Message;
                }
                await writer.WriteLineAsync(reply);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception e) { App.Log("control pipe: " + e.Message); await Task.Delay(500); }
        }
    }

    public void Dispose() => stop.Cancel();
}
