param(
    [string]$ProjectName = "computer_fpga_linux_uart_boot",
    [string]$ProjectDir = "build/computer_fpga_linux_uart_boot",
    [int]$Jobs = 8,
    [int]$ClkFreqHz = 100000000,
    [switch]$DisableFpu
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$drive = $root.Substring(0, 1).ToLowerInvariant()
$rest = $root.Substring(2).Replace("\", "/")
$wslRoot = "/mnt/$drive$rest"

Write-Host "Building UART Linux loader firmware hex via WSL"
wsl bash -lc "cd '$wslRoot' && bash software/scripts/build_linux_uart_loader.sh"

$vivadoArgs = @(
    "-mode", "batch",
    "-source", "script/create_computer_fpga_project.tcl",
    "-tclargs",
    "--build",
    "--project_name", $ProjectName,
    "--project_dir", $ProjectDir,
    "--jobs", "$Jobs",
    "--clk_freq_hz", "$ClkFreqHz",
    "--linux_uart_boot"
)
if ($DisableFpu) {
    $vivadoArgs += "--disable_fpu"
}

Write-Host "Building Vivado bitstream for UART Linux boot"
vivado @vivadoArgs
