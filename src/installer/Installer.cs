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
    private static string _logPath;

    private static int Main(string[] args)
    {
        try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
        try { Console.Title = AppTitle; } catch { }

        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        _logPath = Path.Combine(Path.GetTempPath(), "TrafficityCHT-setup.log");
        try { File.WriteAllText(_logPath, "== " + DateTime.Now.ToString("s") + " ==\r\n"); } catch { }

        try
        {
            return Run(args, exeDir);
        }
        catch (Exception ex)
        {
            Log("[錯誤] " + ex.GetType().Name + ": " + ex.Message);
            Log(ex.StackTrace);
            Console.WriteLine();
            Console.WriteLine("[錯誤] 安裝失敗，詳細記錄：" + _logPath);
            Console.WriteLine("       請把這個檔案回報到 GitHub issue。");
            Pause();
            return 1;
        }
    }

    private static int Run(string[] args, string exeDir)
    {
        Banner();

        bool restore = false;
        string explicitDir = null;
        foreach (string a in args)
        {
            if (a == "--restore" || a == "/restore" || a == "-restore") restore = true;
            else if (!a.StartsWith("-") && !a.StartsWith("/")) explicitDir = a;
        }

        Log("mode=" + (restore ? "restore" : "install"));
        Log("exeDir=" + exeDir);

        string gameDir = FindGameDir(explicitDir, exeDir);
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
        Log("gameDir=" + gameDir);

        bool running = false;
        try
        {
            Process[] ps = Process.GetProcessesByName("Trafficity");
            running = ps.Length > 0;
            for (int i = 0; i < ps.Length; i++) ps[i].Dispose();
        }
        catch (Exception ex)
        {
            Log("process-check failed: " + ex.Message);
        }
        if (running)
        {
            Console.WriteLine("[錯誤] 遊戲正在執行，請先完全關閉遊戲（含 Steam 工作列圖示）。");
            Pause();
            return 1;
        }

        string tempDir = Path.Combine(Path.GetTempPath(), "TrafficityCHT_" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(tempDir);
        Log("temp=" + tempDir);

        try
        {
            string patchPath = Path.Combine(tempDir, "patch.ps1");
            string restorePath = Path.Combine(tempDir, "restore.ps1");
            string zhtPath = Path.Combine(tempDir, "zht.json");

            Extract("patch.ps1", patchPath);
            Extract("restore.ps1", restorePath);
            Extract("zht.json", zhtPath);
            Log("extracted: " + patchPath + " " + new FileInfo(patchPath).Length + " bytes");
            Log("extracted: " + zhtPath + " " + new FileInfo(zhtPath).Length + " bytes");

            string script = restore ? restorePath : patchPath;
            var psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -GameDir \"" + gameDir + "\"";
            psi.UseShellExecute = false;
            psi.WorkingDirectory = tempDir;
            Log("run: " + psi.FileName + " " + psi.Arguments);

            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                Log("child exit=" + p.ExitCode);
                return p.ExitCode;
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }
    }

    private static void Banner()
    {
        Console.WriteLine("==============================================");
        Console.WriteLine("  " + AppTitle);
        Console.WriteLine("  Steam AppID 5185750");
        Console.WriteLine("==============================================");
        Console.WriteLine();
    }

    private static void Log(string message)
    {
        try
        {
            if (!string.IsNullOrEmpty(_logPath)) File.AppendAllText(_logPath, message + "\r\n", Encoding.UTF8);
        }
        catch { }
    }

    private static void Extract(string resourceName, string destPath)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        string[] names = asm.GetManifestResourceNames();
        Log("resources=" + string.Join("|", names));

        Stream stream = null;
        foreach (string n in names)
        {
            if (n == resourceName || n.EndsWith("." + resourceName, StringComparison.OrdinalIgnoreCase))
            {
                stream = asm.GetManifestResourceStream(n);
                break;
            }
        }
        if (stream == null) throw new InvalidOperationException("內嵌資源缺失: " + resourceName);

        using (stream)
        using (FileStream fs = new FileStream(destPath, FileMode.Create, FileAccess.Write))
        {
            byte[] buf = new byte[81920];
            int n;
            while ((n = stream.Read(buf, 0, buf.Length)) > 0) fs.Write(buf, 0, n);
        }
    }

    private static string FindGameDir(string explicitDir, string exeDir)
    {
        var candidates = new List<string>();

        if (!string.IsNullOrEmpty(explicitDir)) candidates.Add(explicitDir);

        string env = Environment.GetEnvironmentVariable("TRAFFICITY_DIR");
        if (!string.IsNullOrEmpty(env)) candidates.Add(env);

        candidates.Add(exeDir);
        try { candidates.Add(Path.GetFullPath(Path.Combine(exeDir, ".."))); } catch { }

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
        catch (Exception ex)
        {
            Log("registry scan failed: " + ex.Message);
        }

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
                if (File.Exists(Path.Combine(full, @"resources\app.asar")))
                {
                    Log("candidate hit: " + full);
                    return full;
                }
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
