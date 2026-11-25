using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length != 2 || (args[1] != "Apply" && args[1] != "Startup"))
            return;

        try
        {
            if (!File.Exists(args[0]))
                throw new FileNotFoundException();

            var powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            var command = "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \"" +
                args[0] + "\" -Action " + args[1] + " -Hidden";
            using (Process process = Process.Start(new ProcessStartInfo(powershell, command)
            {
                UseShellExecute = false,
                CreateNoWindow = true
            })) { }
        }
        catch (Exception)
        {
            if (args[1] == "Apply")
                MessageBox.Show("Reroll.bat または Setup.bat をフォルダーから開いてください。", "壁紙ランダム", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}
