<#
.SYNOPSIS
    Cria a rede e as máquinas virtuais do laboratório no Hyper-V.

.DESCRIPTION
    Executar no computador HOST (Windows 10/11 Pro ou Windows Server com Hyper-V),
    como Administrador. Cria:
      - Switch interno "LAB-Interno" (rede isolada do laboratório)
      - DC01  : Windows Server (AD DS, DNS, DHCP) - 2 GB RAM
      - CLI01 : Windows 11 cliente do domínio       - 4 GB RAM (mínimo do Windows 11)

.PARAMETER IsoServidor
    Caminho da ISO do Windows Server (a versão de avaliação é gratuita por 180 dias).

.PARAMETER IsoCliente
    Caminho da ISO do Windows 10/11.

.PARAMETER PastaVMs
    Onde salvar discos e configurações das VMs.

.EXAMPLE
    .\01-Criar-VMs.ps1 -IsoServidor D:\ISOs\WinServer2022.iso -IsoCliente D:\ISOs\Win11.iso
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$IsoServidor,
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$IsoCliente,
    [string]$PastaVMs = "C:\HyperV\Lab",
    [string]$NomeSwitch = "LAB-Interno"
)

#Requires -RunAsAdministrator
Import-Module Hyper-V -ErrorAction Stop

if (-not (Test-Path $PastaVMs)) { New-Item -ItemType Directory -Path $PastaVMs | Out-Null }

# 1. Rede interna do laboratório
if (-not (Get-VMSwitch -Name $NomeSwitch -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($NomeSwitch, 'Criar switch interno')) {
        New-VMSwitch -Name $NomeSwitch -SwitchType Internal | Out-Null
        Write-Host "Switch '$NomeSwitch' criado."
    }
}

# 2. Definição das VMs
$vms = @(
    @{ Nome = 'DC01';  Iso = $IsoServidor; MemoriaGB = 2; DiscoGB = 60 },
    @{ Nome = 'CLI01'; Iso = $IsoCliente;  MemoriaGB = 4; DiscoGB = 60 }
)

foreach ($vm in $vms) {
    if (Get-VM -Name $vm.Nome -ErrorAction SilentlyContinue) {
        Write-Host "VM $($vm.Nome) já existe, pulando."
        continue
    }

    if ($PSCmdlet.ShouldProcess($vm.Nome, 'Criar VM')) {
        $disco = Join-Path $PastaVMs "$($vm.Nome).vhdx"

        New-VM -Name $vm.Nome `
               -Generation 2 `
               -MemoryStartupBytes ($vm.MemoriaGB * 1GB) `
               -NewVHDPath $disco `
               -NewVHDSizeBytes ($vm.DiscoGB * 1GB) `
               -SwitchName $NomeSwitch `
               -Path $PastaVMs | Out-Null

        Set-VMProcessor -VMName $vm.Nome -Count 2
        Set-VMMemory    -VMName $vm.Nome -DynamicMemoryEnabled $true -MinimumBytes ($vm.MemoriaGB * 512MB) -MaximumBytes ($vm.MemoriaGB * 1GB)

        Add-VMDvdDrive -VMName $vm.Nome -Path $vm.Iso
        $dvd = Get-VMDvdDrive -VMName $vm.Nome
        Set-VMFirmware -VMName $vm.Nome -FirstBootDevice $dvd

        # Windows 11 exige TPM
        Set-VMKeyProtector -VMName $vm.Nome -NewLocalKeyProtector
        Enable-VMTPM -VMName $vm.Nome

        Write-Host "VM $($vm.Nome) criada. Inicie com: Start-VM $($vm.Nome)"
    }
}

Write-Host "`nPróximo passo: instalar o Windows nas VMs e rodar 02-Configurar-DC.ps1 dentro da DC01."
