using System.IO;
using SherpaOnnx;
using Softly.Core;

namespace Softly;

/// <summary>
/// The two engines behind one interface: whisper.cpp (Transcriber) and
/// Parakeet (ParakeetTranscriber). DictationEngine talks to whichever the
/// current speech model uses.
/// </summary>
public interface ISpeechBackend
{
    string Backend { get; }
    Task<Transcriber.Status> LoadAsync(string path);
    Task<string?> TranscribeAsync(float[] samples, string earlier = "");
    /// <summary>Frees the model's memory when the other engine takes over.</summary>
    void Unload();
}

/// <summary>
/// NVIDIA Parakeet TDT v3 (int8) through sherpa-onnx, on the CPU. The four
/// model files live in their own folder under Models; ModelDownloader
/// fetches them.
/// </summary>
public sealed class ParakeetTranscriber : ISpeechBackend
{
    private OfflineRecognizer? recognizer;
    private readonly SemaphoreSlim gate = new(1, 1);

    public string Backend => recognizer == null ? "" : "CPU";

    public async Task<Transcriber.Status> LoadAsync(string folder)
    {
        await gate.WaitAsync();
        try
        {
            if (!SpeechModel.Parakeet.IsDownloaded) return Transcriber.Status.MissingModel;
            recognizer?.Dispose();
            recognizer = null;
            var config = new OfflineRecognizerConfig();
            config.ModelConfig.Transducer.Encoder = Path.Combine(folder, "encoder.int8.onnx");
            config.ModelConfig.Transducer.Decoder = Path.Combine(folder, "decoder.int8.onnx");
            config.ModelConfig.Transducer.Joiner = Path.Combine(folder, "joiner.int8.onnx");
            config.ModelConfig.Tokens = Path.Combine(folder, "tokens.txt");
            config.ModelConfig.ModelType = "nemo_transducer";
            config.ModelConfig.NumThreads = Settings.Threads;
            config.ModelConfig.Provider = "cpu";
            config.DecodingMethod = "greedy_search";
            recognizer = await Task.Run(() => new OfflineRecognizer(config));
            return Transcriber.Status.Ready;
        }
        catch (Exception)
        {
            return Transcriber.Status.Failed;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>Parakeet takes no prompt, so <paramref name="earlier"/> is unused.</summary>
    public async Task<string?> TranscribeAsync(float[] samples, string earlier = "")
    {
        await gate.WaitAsync();
        try
        {
            var r = recognizer;
            if (r == null) return null;
            var audio = Transcript.Padded(samples);
            var text = await Task.Run(() =>
            {
                using var stream = r.CreateStream();
                stream.AcceptWaveform(Chunking.SampleRate, audio);
                r.Decode(stream);
                return stream.Result.Text;
            });
            return Transcript.Clean(new[] { text });
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            gate.Release();
        }
    }

    public void Unload()
    {
        gate.Wait();
        try { recognizer?.Dispose(); recognizer = null; }
        finally { gate.Release(); }
    }
}
