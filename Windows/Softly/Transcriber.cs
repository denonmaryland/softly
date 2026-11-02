using System.IO;
using Softly.Core;
using Whisper.net;

namespace Softly;

/// <summary>
/// Local Whisper transcription through whisper.cpp (Whisper.net). The model
/// stays loaded so each dictation only pays for inference. Vulkan is used
/// when the GPU driver supports it, otherwise the CPU build.
/// </summary>
public sealed class Transcriber : IDisposable
{
    public enum Status { Loading, Ready, MissingModel, Failed }

    private WhisperFactory? factory;
    private readonly SemaphoreSlim gate = new(1, 1);

    public string Backend { get; private set; } = "";

    public async Task<Status> LoadAsync(string path)
    {
        await gate.WaitAsync();
        try
        {
            if (!File.Exists(path)) return Status.MissingModel;
            factory?.Dispose();
            factory = null;
            factory = await Task.Run(() => WhisperFactory.FromPath(path));
            Backend = Whisper.net.LibraryLoader.RuntimeOptions.LoadedLibrary?.ToString() ?? "";
            return Status.Ready;
        }
        catch (Exception)
        {
            return Status.Failed;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// Returns cleaned text, or null when nothing was said or decoding failed.
    /// <paramref name="earlier"/> is the text just before this audio, when it is a
    /// later piece of a longer recording; it keeps spelling and casing in step.
    /// </summary>
    public async Task<string?> TranscribeAsync(float[] samples, string earlier = "")
    {
        await gate.WaitAsync();
        try
        {
            var f = factory;
            if (f == null) return null;
            var audio = Transcript.Padded(samples);
            var tail = earlier.Length > 200 ? earlier[^200..] : earlier;
            var prompt = string.Join(" ", new[] { Settings.InitialPrompt, tail }.Where(p => p.Length > 0));
            var builder = f.CreateBuilder()
                .WithThreads(Settings.Threads)
                .WithNoContext();
            builder = Settings.Language == "auto" ? builder.WithLanguageDetection() : builder.WithLanguage(Settings.Language);
            if (prompt.Length > 0) builder = builder.WithPrompt(prompt);
            var segments = new List<string>();
            await Task.Run(async () =>
            {
                await using var processor = builder.Build();
                await foreach (var segment in processor.ProcessAsync(audio))
                    segments.Add(segment.Text);
            });
            return Transcript.Clean(segments);
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

    public void Dispose()
    {
        factory?.Dispose();
        factory = null;
    }
}
