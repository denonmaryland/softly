using System.IO;

namespace Softly;

/// <summary>
/// The speech models Softly offers. All three are whisper.cpp files from the
/// same Hugging Face repo, so the engine and the download path are shared;
/// they trade size and speed for accuracy. Same list, ids and checksums as
/// Sources/Softly/SpeechModel.swift.
/// </summary>
public sealed record SpeechModel(string Id, string Name, string Detail, string FileName, string Sha256, int SizeMB)
{
    public string Url => "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + FileName;

    public static readonly SpeechModel Fast = new(
        "fast", "Fast", "Smallest and quickest. Fine for short, plain sentences.",
        "ggml-base.en-q5_1.bin", "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f", 60);
    public static readonly SpeechModel Balanced = new(
        "balanced", "Balanced", "The default. Quick, and good with everyday speech.",
        "ggml-small.en-q5_1.bin", "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30", 190);
    public static readonly SpeechModel Accurate = new(
        "accurate", "Accurate", "Best with names, code and technical words. Slower without a GPU.",
        "ggml-large-v3-turbo-q5_0.bin", "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", 574);

    public static readonly SpeechModel[] All = { Fast, Balanced, Accurate };

    public static SpeechModel With(string id) => All.FirstOrDefault(m => m.Id == id) ?? Balanced;

    public static SpeechModel Current => With(Settings.SpeechModel);

    public string FilePath => Path.Combine(Settings.ModelDirectory, FileName);

    public bool IsDownloaded => File.Exists(FilePath);
}
