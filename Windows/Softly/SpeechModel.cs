using System.IO;
using Softly.Core;

namespace Softly;

/// <summary>One downloadable whisper.cpp model file.</summary>
public sealed record ModelFile(string Name, string Sha256, int SizeMB)
{
    public string Url => "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + Name;
    public string FilePath => Path.Combine(Settings.ModelDirectory, Name);
}

/// <summary>
/// The speech models Softly offers. All are whisper.cpp files from the same
/// Hugging Face repo, so the engine and the download path are shared; they
/// trade size and speed for accuracy. Fast and Balanced come as an
/// English-only file and a multilingual one, picked by the language setting.
/// Same list, ids and checksums as Sources/Softly/SpeechModel.swift.
/// </summary>
public sealed record SpeechModel(string Id, string Name, string Detail, ModelFile English, ModelFile Multilingual)
{
    private static readonly ModelFile Turbo = new("ggml-large-v3-turbo-q5_0.bin", "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", 574);

    public static readonly SpeechModel Fast = new(
        "fast", "Fast", "Smallest and quickest. Fine for short, plain sentences.",
        new("ggml-base.en-q5_1.bin", "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f", 60),
        new("ggml-base-q5_1.bin", "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898", 60));
    public static readonly SpeechModel Balanced = new(
        "balanced", "Balanced", "The default. Quick, and good with everyday speech.",
        new("ggml-small.en-q5_1.bin", "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30", 190),
        new("ggml-small-q5_1.bin", "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", 190));
    public static readonly SpeechModel Accurate = new(
        "accurate", "Accurate", "Best with names, code and technical words. Slower without a GPU.", Turbo, Turbo);

    public static readonly SpeechModel[] All = { Fast, Balanced, Accurate };

    public static SpeechModel With(string id) => All.FirstOrDefault(m => m.Id == id) ?? Balanced;

    public static SpeechModel Current => With(Settings.SpeechModel);

    /// <summary>The file this model needs for the language setting.</summary>
    public ModelFile File => Languages.NeedsMultilingual(Settings.Language) ? Multilingual : English;

    public int SizeMB => File.SizeMB;

    public string FilePath => File.FilePath;

    public bool IsDownloaded => System.IO.File.Exists(FilePath);
}
