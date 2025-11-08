Set Shell = CreateObject("Shell.Application")
Shell.ShellExecute "powershell", "-executionpolicy bypass .\deskcreen_virtual.ps1", , "runas", 0
