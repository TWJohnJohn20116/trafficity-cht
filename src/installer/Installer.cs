using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

internal static class Program
{
    private const string AppTitle = "Trafficity 繁體中文（台灣）漢化";

    private static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        try { Console.Title = AppTitle; } catch { }

        Console.WriteLine("==============================================");
        Console.WriteLine("  " + AppTitle);
        Console.WriteLine("  Steam AppID 5185750");
        Console.WriteLine("==============================================");
        Console.WriteLine();

        bool restore = false;
        string explicitDir = null;
        foreach (string a in args)
        {
            if (a == "--restore" || a == "/restore" || a == "-restore") restore = true;
            else if (!a.StartsWith("-") && !a.StartsWith("/")) explicitDir = a;
        }

        string gameDir = FindGameDir(explicitDir);
        if (gameDir == null)
        {
            Console.WriteLine("[錯誤] 找不到 Trafficity 遊戲資料夾（缺少 resources\app.asar）。");
            Console.WriteLine();
            Console.WriteLine("  請把本程式放進遊戲根目錄後再執行，例如：");
            Console.WriteLine(@"  D:\SteamLibrary\steamapps\common\Trafficity\");
            Console.WriteLine();
            Console.WriteLine("  或指定路徑：");
            Console.WriteLine("  Trafficity-CHT-Setup.exe \"D:\\SteamLibrary\\steamapps\\common\\Trafficity\"");
            Pause();
            return 1;
        }

        Console.WriteLine("遊戲目錄: " + gameDir);
        Console.WriteLine("模式: " + (restore ? "還原原版" : "安裝繁體中文"));
        Console.WriteLine();

        if (Process.GetProcessesByName("Trafficity").Length > 0)
        {
            Console.WriteLine("[錯誤] 遊戲正在執行，請先完全關閉遊戲（含 Steam 工作列圖示）。");
            Pause();
            return 1;
        }

        string tempDir = Path.Combine(Path.GetTempPath(), "TrafficityCHT_" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(tempDir);
        try
        {
            string patchPath = Path.Combine(tempDir, "patch.ps1");
            string restorePath = Path.Combine(tempDir, "restore.ps1");
            string zhtPath = Path.Combine(tempDir, "zht.json");
            Extract("patch.ps1", patchPath);
            Extract("restore.ps1", restorePath);
            Extract("zht.json", zhtPath);

            string script = restore ? restorePath : patchPath;
            var psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -GameDir \"" + gameDir + "\"";
            psi.UseShellExecute = false;
            psi.WorkingDirectory = tempDir;

            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }
    }

    private static void Extract(string resourceName, string destPath)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        using (Stream s = asm.GetManifestResourceStream(resourceName))
        {
            if (s == null) throw new InvalidOperationException("內嵌資源缺失: " + resourceName);
            using (FileStream fs = new FileStream(destPath, FileMode.Create, FileAccess.Write))
            {
                byte[] buf = new byte[81920];
                int n;
                while ((n = s.Read(buf, 0, buf.Length)) > 0) fs.Write(buf, 0, n);
            }
        }
    }

    private static string FindGameDir(string explicitDir)
    {
        var candidates = new List<string>();

        if (!string.IsNullOrEmpty(explicitDir)) candidates.Add(explicitDir);

        string env = Environment.GetEnvironmentVariable("TRAFFICITY_DIR");
        if (!string.IsNullOrEmpty(env)) candidates.Add(env);

        string here = AppDomain.CurrentDomain.BaseDirectory;
        candidates.Add(here);
        try { candidates.Add(Path.GetFullPath(Path.Combine(here, ".."))); } catch { }

        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
            {
                string steamPath = k == null ? null : k.GetValue("SteamPath") as string;
                if (!string.IsNullOrEmpty(steamPath))
                {
                    steamPath = steamPath.Replace('/', '\\');
                    candidates.Add(Path.Combine(steamPath, @"steamapps\common\Trafficity"));

                    string vdf = Path.Combine(steamPath, @"steamapps\libraryfolders.vdf");
                    if (File.Exists(vdf))
                    {
                        foreach (string line in File.ReadAllLines(vdf))
                        {
                            Match m = Regex.Match(line, "\"path\"\\s+\"([^\"]+)\"");
                            if (m.Success)
                            {
                                string lib = m.Groups[1].Value.Replace("\\\\", "\\");
                                candidates.Add(Path.Combine(lib, @"steamapps\common\Trafficity"));
                            }
                        }
                    }
                }
            }
        }
        catch { }

        foreach (string root in new string[] { @"D:\SteamLibrary", @"E:\SteamLibrary", @"F:\SteamLibrary", @"G:\SteamLibrary", @"C:\Program Files (x86)\Steam" })
        {
            candidates.Add(Path.Combine(root, @"steamapps\common\Trafficity"));
        }

        foreach (string c in candidates)
        {
            if (string.IsNullOrEmpty(c)) continue;
            try
            {
                string full = Path.GetFullPath(c);
                if (File.Exists(Path.Combine(full, @"resources\app.asar"))) return full;
            }
            catch { }
        }
        return null;
    }

    private static void Pause()
    {
        Console.WriteLine();
        Console.WriteLine("按任意鍵結束...");
        try { Console.ReadKey(true); } catch { }
    }
}
