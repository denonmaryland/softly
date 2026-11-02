using System.IO;
using Softly.Core;

namespace Softly;

/// <summary>One downloadable model file; whisper.cpp's unless another repo and folder are given.</summary>
public sealed record ModelFile(string Name, string Sha256, int SizeMB, string Repo = "ggerganov/whisper.cpp", string Folder = "")
{
    public string Url => $"https://huggingface.co/{Repo}/resolve/main/{Name}";
    public string FilePath => Path.Combine(Settings.ModelDirectory, Folder, Name);
}

public enum SpeechEngine { Whisper, Parakeet }

/// <summary>
/// The speech models Softly offers. All are whisper.cpp files from the same
/// Hugging Face repo, so the engine and the download path are shared; they
/// trade size and speed for accuracy. Fast and Balanced come as an
/// English-only file and a multilingual one, picked by the language setting.
/// Same list, ids and checksums as Sources/Softly/SpeechModel.swift.
/// </summary>
public sealed record SpeechModel(string Id, string Name, string Detail, ModelFile English, ModelFile Multilingual,
                                 SpeechEngine Engine = SpeechEngine.Whisper, ModelFile[]? Parts = null)
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

    /// <summary>
    /// NVIDIA Parakeet TDT v3 (int8) through sherpa-onnx on the CPU: four files
    /// in their own folder. It detects 25 European languages by itself and
    /// takes no vocabulary hints; fixes still apply.
    /// </summary>
    public static readonly SpeechModel Parakeet = MakeParakeet();

    private static SpeechModel MakeParakeet()
    {
        const string repo = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8", folder = "parakeet-tdt-0.6b-v3-int8";
        var parts = new ModelFile[]
        {
            new("encoder.int8.onnx", "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247", 652, repo, folder),
            new("decoder.int8.onnx", "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e", 12, repo, folder),
            new("joiner.int8.onnx", "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3", 6, repo, folder),
            new("tokens.txt", "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d", 1, repo, folder),
        };
        return new("parakeet", "Parakeet", "Fast on the CPU. 25 languages; no vocabulary hints.",
                   parts[0], parts[0], SpeechEngine.Parakeet, parts);
    }

    public static readonly SpeechModel[] All = { Fast, Balanced, Accurate, Parakeet };

    public static SpeechModel With(string id) => All.FirstOrDefault(m => m.Id == id) ?? Balanced;

    public static SpeechModel Current => With(Settings.SpeechModel);

    /// <summary>The file this model needs for the language setting.</summary>
    public ModelFile File => Languages.NeedsMultilingual(Settings.Language) ? Multilingual : English;

    /// <summary>Every file this model needs for the language setting.</summary>
    public ModelFile[] Files => Parts ?? new[] { File };

    public int SizeMB => Files.Sum(f => f.SizeMB);

    /// <summary>The whisper.cpp file, or Parakeet's folder.</summary>
    public string FilePath => Parts != null ? Path.GetDirectoryName(Parts[0].FilePath)! : File.FilePath;

    public bool IsDownloaded => Files.All(f => System.IO.File.Exists(f.FilePath));
}
