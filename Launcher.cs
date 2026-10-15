using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.Reflection;

[assembly: AssemblyTitle("NASA 朋克主题")]
[assembly: AssemblyProduct("NASA 朋克主题")]
[assembly: AssemblyVersion("0.7.3.0")]
[assembly: AssemblyFileVersion("0.7.3.0")]

internal static class Launcher
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AttachConsole(int processId);

    private static void AttachParentConsole()
    {
        if (!AttachConsole(-1)) return;
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true });
        Console.SetError(new StreamWriter(Console.OpenStandardError()) { AutoFlush = true });
    }

    private const int Success = 0;
    private const int UserActionRequired = 2;

    internal static void StopRedirectedReads(Process process)
    {
        // The app and watchers can inherit a pipe. Do not wait for reader EOF
        // on the UI thread after the actual installation process has exited.
        try { process.CancelOutputRead(); } catch (InvalidOperationException) { }
        try { process.CancelErrorRead(); } catch (InvalidOperationException) { }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string exeName = Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
            bool isStart = String.Equals(exeName, "ChatGPT-NASA", StringComparison.OrdinalIgnoreCase);
            if (isStart) root = Directory.GetParent(root.TrimEnd(Path.DirectorySeparatorChar)).FullName;
            string files = Path.Combine(root, "files");
            string install = Path.Combine(files, "install-package.ps1");
            string uninstall = Path.Combine(files, "uninstall-package.ps1");
            string start = Path.Combine(files, "start-package.ps1");

            if (args.Length == 1 && String.Equals(args[0], "--check", StringComparison.OrdinalIgnoreCase))
            {
                AttachParentConsole();
                bool installExists = File.Exists(install);
                bool uninstallExists = File.Exists(uninstall);
                Console.WriteLine("{\"installScript\":\"" + JsonEscape(install) + "\",\"installExists\":" + installExists.ToString().ToLowerInvariant() +
                    ",\"uninstallScript\":\"" + JsonEscape(uninstall) + "\",\"uninstallExists\":" + uninstallExists.ToString().ToLowerInvariant() + "}");
                return installExists && uninstallExists && File.Exists(start) ? Success : 1;
            }
            if (args.Length != 0)
            {
                Console.Error.WriteLine("用法：Launcher.exe [--check]");
                return 1;
            }

            bool isUninstall = exeName.IndexOf("卸载", StringComparison.Ordinal) >= 0;
            string script = isStart ? start : (isUninstall ? uninstall : install);
            if (!File.Exists(script))
            {
                MessageBox.Show("未找到所需操作脚本：\r\n" + script + "\r\n\r\n请确认程序与 files 文件夹位于同一目录。", "NASA 朋克主题", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            if (script.IndexOf('"') >= 0)
            {
                MessageBox.Show("操作脚本路径包含不支持的双引号，无法安全启动。", "NASA 朋克主题", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (LauncherForm form = new LauncherForm(script, isUninstall, isStart))
            {
                Application.Run(form);
                return form.ResultCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("启动器遇到错误：\r\n" + ex.Message, "NASA 朋克主题", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string JsonEscape(string value)
    {
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
    }

    private static string QuoteArgument(string value)
    {
        if (value.IndexOf('"') >= 0) throw new ArgumentException("Path contains a double quote.");
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"')
            {
                result.Append('\\', slashes * 2 + 1).Append(c);
                slashes = 0;
                continue;
            }
            result.Append('\\', slashes).Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2).Append('"');
        return result.ToString();
    }

    private sealed class LauncherForm : Form
    {
        private readonly string script;
        private readonly bool uninstall;
        private readonly bool start;
        private readonly string logPath;
        private readonly Label heading;
        private readonly Label status;
        private readonly TextBox logLabel;
        private readonly ProgressBar progress;
        private readonly Button closeButton;
        private readonly Button openLogButton;
        private readonly Timer timer;
        private readonly object logLock = new object();
        private Process child;
        private bool finished;
        private int resultCode = 1;
        private bool logFailed;
        private volatile bool cleanupPending;
        private DateTime? exitObservedAt;

        public int ResultCode { get { return resultCode; } private set { resultCode = value; } }

        public LauncherForm(string scriptPath, bool isUninstall, bool isStart)
        {
            script = scriptPath;
            uninstall = isUninstall;
            start = isStart;
            string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexDreamSkin", "logs");
            Directory.CreateDirectory(logDir);
            logPath = Path.Combine(logDir, "launcher-" + (start ? "start-" : (uninstall ? "uninstall-" : "install-")) + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + ".log");

            Text = start ? "启动 ChatGPT · NASA 朋克" : (uninstall ? "卸载外观" : "安装外观");
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = true;
            ClientSize = new Size(520, 214);
            Font = new Font("Microsoft YaHei UI", 9F, FontStyle.Regular, GraphicsUnit.Point);

            heading = new Label { Left = 22, Top = 20, Width = 476, Height = 25, Font = new Font(Font, FontStyle.Bold), Text = start ? "正在启动客户端与主题" : (uninstall ? "正在卸载主题" : "正在准备安装主题") };
            status = new Label { Left = 22, Top = 55, Width = 476, Height = 43, Text = "正在启动操作脚本……\r\n关闭此窗口不会停止正在运行的操作。" };
            progress = new ProgressBar { Left = 22, Top = 106, Width = 476, Height = 18, Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 25 };
            logLabel = new TextBox { Left = 22, Top = 132, Width = 476, Height = 34, Text = "日志：" + logPath, Multiline = true, ReadOnly = true, WordWrap = true, BorderStyle = BorderStyle.FixedSingle, TabStop = false };
            openLogButton = new Button { Left = 22, Top = 174, Width = 108, Height = 27, Text = "打开日志", Enabled = false };
            closeButton = new Button { Left = 390, Top = 174, Width = 108, Height = 27, Text = "最小化" };
            Controls.AddRange(new Control[] { heading, status, progress, logLabel, openLogButton, closeButton });
            AcceptButton = closeButton;
            closeButton.Click += delegate { if (finished) Close(); else WindowState = FormWindowState.Minimized; };
            openLogButton.Click += delegate { OpenLog(); };
            timer = new Timer { Interval = 300 };
            timer.Tick += PollProcess;
            Shown += StartOperation;
            FormClosing += delegate(object sender, FormClosingEventArgs e)
            {
                if (finished) return;
                e.Cancel = true;
                status.Text = "操作仍在运行。请最小化窗口，等待完成后再关闭。";
            };
            FormClosed += delegate { timer.Stop(); timer.Dispose(); if (child != null) child.Dispose(); };
        }

        private void StartOperation(object sender, EventArgs e)
        {
            try
            {
                File.AppendAllText(logPath, "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + (start ? "开始启动" : (uninstall ? "开始卸载" : "开始安装")) + "\r\n脚本：" + script + "\r\n", new UTF8Encoding(false));
                string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
                if (!File.Exists(powershell)) powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
                ProcessStartInfo info = new ProcessStartInfo();
                info.FileName = powershell;
                info.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File " + QuoteArgument(script);
                if (uninstall) info.Arguments += " -WaitForLauncherPid " + Process.GetCurrentProcess().Id;
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;
                info.StandardOutputEncoding = Encoding.UTF8;
                info.StandardErrorEncoding = Encoding.UTF8;
                info.WorkingDirectory = Path.GetDirectoryName(script);
                child = new Process();
                child.StartInfo = info;
                child.EnableRaisingEvents = true;
                child.OutputDataReceived += OnOutput;
                child.ErrorDataReceived += OnError;
                child.Start();
                IntPtr retainedHandle = child.Handle;
                child.BeginOutputReadLine();
                child.BeginErrorReadLine();
                openLogButton.Enabled = true;
                status.Text = "操作正在运行，请稍候。\r\n关闭此窗口不会停止操作脚本。";
                timer.Start();
            }
            catch (Exception ex)
            {
                WriteLog("启动失败：" + ex);
                ShowFinished("无法启动操作脚本。请查看日志。", false);
            }
        }

        private void OnOutput(object sender, DataReceivedEventArgs e)
        {
            if (e.Data == null) return;
            if (e.Data == "NASA-PACKAGE-CLEANUP-PENDING") cleanupPending = true;
            WriteLog(e.Data);
            const string prefix = "NASA-PACKAGE-STAGE:";
            if (e.Data.StartsWith(prefix, StringComparison.Ordinal) && !IsDisposed && IsHandleCreated)
            {
                string stage = e.Data.Substring(prefix.Length);
                try { BeginInvoke(new Action(delegate { if (!finished) { heading.Text = stage; status.Text = "操作正在运行，请稍候。\r\n可随时打开日志查看处理进度。"; } })); }
                catch (InvalidOperationException) { }
            }
        }
        private void OnError(object sender, DataReceivedEventArgs e) { if (e.Data != null) WriteLog("[stderr] " + e.Data); }

        private void PollProcess(object sender, EventArgs e)
        {
            if (finished || child == null) return;
            try
            {
                if (!child.HasExited) return;
                // Allow one timer turn for queued final log lines, without
                // waiting for EOF on handles inherited by persistent children.
                if (!exitObservedAt.HasValue) { exitObservedAt = DateTime.UtcNow; return; }
                if ((DateTime.UtcNow - exitObservedAt.Value).TotalMilliseconds < 250) return;
                int code = child.ExitCode;
                timer.Stop();
                StopRedirectedReads(child);
                WriteLog("操作脚本已结束，退出代码：" + code);
                if (code == Success)
                {
                    ShowFinished(start ? "客户端与主题已启动。" : (uninstall ? (cleanupPending ? "外观已恢复。关闭此窗口后，程序会清理自身文件；清理结果另记入日志。" : "没有需要继续处理的安装。") : "桌面已创建“ChatGPT · NASA 朋克”启动入口。\r\n以后使用此入口；可将它固定到任务栏。"), true);
                    if (start) Close();
                }
                else if (code == UserActionRequired)
                    ShowFinished("检测到 ChatGPT 或 Codex 仍在运行。请手动退出相关应用，再重新运行本程序。", false);
                else
                    ShowFinished("操作未能完成（退出代码 " + code + "）。请查看日志了解详情。", false);
            }
            catch (Exception ex)
            {
                timer.Stop();
                WriteLog("读取脚本状态失败：" + ex);
                ShowFinished("无法确认操作结果。请查看日志。", false);
            }
        }

        private void ShowFinished(string message, bool success)
        {
            finished = true;
            ResultCode = success ? Success : 1;
            progress.Style = ProgressBarStyle.Blocks;
            progress.MarqueeAnimationSpeed = 0;
            progress.Value = success ? 100 : 0;
            heading.Text = success ? (start ? "启动完成" : (uninstall ? (cleanupPending ? "外观已恢复，等待退出清理" : "操作完成") : "安装完成")) : "操作需要处理";
            status.Text = message + "\r\n关闭此窗口不会终止已启动的脚本。";
            if (message.StartsWith("检测到 ChatGPT")) ResultCode = UserActionRequired;
            openLogButton.Enabled = File.Exists(logPath);
            closeButton.Text = "关闭窗口";
            Text = success ? "操作完成" : "操作结果";
        }

        private void WriteLog(string line)
        {
            try
            {
                lock (logLock) File.AppendAllText(logPath, line + Environment.NewLine, new UTF8Encoding(false));
            }
            catch { logFailed = true; }
        }

        private void OpenLog()
        {
            try { Process.Start(new ProcessStartInfo { FileName = logPath, UseShellExecute = true }); }
            catch (Exception ex) { MessageBox.Show(this, "无法打开日志：\r\n" + ex.Message + (logFailed ? "\r\n日志写入也曾失败。" : ""), "NASA 朋克主题", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        }
    }
}
