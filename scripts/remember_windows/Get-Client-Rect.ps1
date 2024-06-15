Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
}
public struct RECT
{
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
public struct POINT
{
    public int x;
    public int y;
}
"@

$Handle = (Get-Process -Id $Args[0]).MainWindowHandle
$ClientRect = New-Object RECT
$Position = New-Object POINT
$Size = New-Object POINT

[Window]::GetClientRect($Handle, [ref]$ClientRect) | out-null
$Position.x = 0 # $ClientRect.Left is always 0
$Position.y = 0 # $ClientRect.Top
$Size.x = $ClientRect.Right
$Size.y = $ClientRect.Bottom
[Window]::ClientToScreen($Handle, [ref]$Position) | out-null

Write-Output "$($Position.x) $($Position.y) $($Size.x) $($Size.y)"