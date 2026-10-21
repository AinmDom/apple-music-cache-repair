' SPDX-License-Identifier: MIT
' Optional hidden launcher. Install falls back to PowerShell if unavailable.
Option Explicit
Dim shell, fs, folder, mode, target, ps, command, result
If WScript.Arguments.Count <> 1 Then WScript.Quit 64
mode = LCase(WScript.Arguments(0))
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
folder = fs.GetParentFolderName(WScript.ScriptFullName)
If mode = "repair" Then
    target = fs.BuildPath(folder, "Repair.ps1")
ElseIf mode = "background" Or mode = "probe" Then
    target = fs.BuildPath(folder, "Background.ps1")
Else
    WScript.Quit 64
End If
If Not fs.FileExists(target) Then WScript.Quit 2
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = Chr(34) & ps & Chr(34) & " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & target & Chr(34)
If mode = "probe" Then command = command & " -Probe"
On Error Resume Next
result = shell.Run(command, 0, True)
If Err.Number <> 0 Then WScript.Quit 1
On Error GoTo 0
WScript.Quit result
