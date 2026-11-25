using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace Freely.MonitorWallpaper
{
    public sealed class DesktopWallpaper : IDisposable
    {
        private const int AttachedToDesktop = 1;
        private const int GetDeviceInterfaceName = 1;
        private const uint SlideshowConfigured = 2;
        private const uint Span = 5;

        private readonly IDesktopWallpaper desktop;

        public DesktopWallpaper()
        {
            desktop = (IDesktopWallpaper)new DesktopWallpaperClass();
        }

        public bool UsesSlideshow
        {
            get
            {
                uint state;
                desktop.GetStatus(out state);
                return (state & SlideshowConfigured) != 0;
            }
        }

        public bool UsesSpan
        {
            get
            {
                uint position;
                desktop.GetPosition(out position);
                return position == Span;
            }
        }

        public sealed class Monitor
        {
            public int Number { get; private set; }
            public string Id { get; private set; }

            internal Monitor(int number, string id)
            {
                Number = number;
                Id = id;
            }
        }

        public List<Monitor> GetMonitors()
        {
            // The wallpaper API's indices also include detached monitors. Match its
            // device paths to the active Windows display names (DISPLAY1, DISPLAY2, ...).
            var activeIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            uint count;
            desktop.GetMonitorDevicePathCount(out count);
            for (uint index = 0; index < count; index++)
            {
                string id;
                desktop.GetMonitorDevicePathAt(index, out id);
                Rect rect;
                int result = desktop.GetMonitorRect(id, out rect);
                Marshal.ThrowExceptionForHR(result);
                if (result == 0)
                    activeIds[id] = id;
            }

            var monitors = new List<Monitor>();
            for (uint index = 0; ; index++)
            {
                var adapter = DisplayDevice.Create();
                if (!EnumDisplayDevices(null, index, ref adapter, 0))
                    break;

                var match = Regex.Match(adapter.DeviceName, @"^\\\\\.\\DISPLAY([0-9]+)$",
                    RegexOptions.IgnoreCase);
                if ((adapter.StateFlags & AttachedToDesktop) == 0 || !match.Success)
                    continue;

                var devices = new List<DisplayDevice>();
                for (uint deviceIndex = 0; ; deviceIndex++)
                {
                    var device = DisplayDevice.Create();
                    if (!EnumDisplayDevices(adapter.DeviceName, deviceIndex, ref device, GetDeviceInterfaceName))
                        break;
                    if ((device.StateFlags & AttachedToDesktop) != 0)
                        devices.Add(device);
                }

                // Mirrored physical monitors can share a display name.
                string monitorId;
                if (devices.Count == 1 && activeIds.TryGetValue(devices[0].DeviceId, out monitorId))
                    monitors.Add(new Monitor(int.Parse(match.Groups[1].Value), monitorId));
            }

            return monitors;
        }

        public string GetWallpaper(string monitorId)
        {
            string image;
            desktop.GetWallpaper(monitorId, out image);
            return image;
        }

        public void SetWallpaper(string monitorId, string image)
        {
            if (string.IsNullOrEmpty(monitorId))
                throw new ArgumentException("A monitor ID is required.", "monitorId");
            desktop.SetWallpaper(monitorId, image);
        }

        public void Dispose()
        {
            Marshal.ReleaseComObject(desktop);
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DisplayDevice
        {
            private int size;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] private string deviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceId;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] private string deviceKey;

            internal static DisplayDevice Create()
            {
                return new DisplayDevice { size = Marshal.SizeOf(typeof(DisplayDevice)) };
            }
        }

        [DllImport("user32.dll", EntryPoint = "EnumDisplayDevicesW", CharSet = CharSet.Unicode, ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplayDevices(string deviceName, uint deviceIndex, ref DisplayDevice device, int flags);

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left, Top, Right, Bottom;
        }

        [ComImport, Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD")]
        private class DesktopWallpaperClass { }

        [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDesktopWallpaper
        {
            void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] string image);
            void GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] out string image);
            void GetMonitorDevicePathAt(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string monitorId);
            void GetMonitorDevicePathCount(out uint count);
            [PreserveSig] int GetMonitorRect([MarshalAs(UnmanagedType.LPWStr)] string monitorId, out Rect rect);
            void SetBackgroundColor(uint color);
            void GetBackgroundColor(out uint color);
            void SetPosition(uint position);
            void GetPosition(out uint position);
            void SetSlideshow(IntPtr items);
            void GetSlideshow(out IntPtr items);
            void SetSlideshowOptions(uint options, uint milliseconds);
            void GetSlideshowOptions(out uint options, out uint milliseconds);
            void AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorId, uint direction);
            void GetStatus(out uint state);
        }
    }
}
