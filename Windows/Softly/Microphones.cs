using NAudio.CoreAudioApi;

namespace Softly;

/// <summary>
/// The PC's active recording devices, for the microphone picker. A device
/// is saved by its endpoint ID; an empty ID follows the Windows default.
/// </summary>
public static class Microphones
{
    public sealed record Device(string Id, string Name);

    public static List<Device> All()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            return enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
                .Select(d => new Device(d.ID, d.FriendlyName))
                .OrderBy(d => d.Name)
                .ToList();
        }
        catch (Exception)
        {
            return new List<Device>();
        }
    }

    /// <summary>The device for a saved ID if it is plugged in; null means use the default.</summary>
    public static MMDevice? Find(string id)
    {
        if (id.Length == 0) return null;
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            var device = enumerator.GetDevice(id);
            return device.State == DeviceState.Active ? device : null;
        }
        catch (Exception)
        {
            return null;
        }
    }
}
