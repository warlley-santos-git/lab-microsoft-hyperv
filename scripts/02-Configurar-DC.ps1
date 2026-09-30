<#
.SYNOPSIS
    Configura a DC01 como controlador de domínio (AD DS + DNS).

.DESCRIPTION
    Executar DENTRO da VM DC01, como Administrador, em duas etapas:

      Etapa 1: renomeia o servidor, define IP fixo e reinicia.
      Etapa 2: instala AD DS e DNS e cria a floresta (reinicia no final).

.EXAMPLE
    .\02-Configurar-DC.ps1 -Etapa 1
    # depois do reinício:
    .\02-Configurar-DC.ps1 -Etapa 2 -Dominio lab.local -NetBIOS LAB
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet(1, 2)][int]$Etapa,
    [string]$NomeServidor = 'DC01',
    [string]$IP           = '192.168.100.10',
    [int]$Prefixo         = 24,
    [string]$Dominio      = 'lab.local',
    [string]$NetBIOS      = 'LAB'
)

#Requires -RunAsAdministrator

switch ($Etapa) {
    1 {
        $placa = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
        if (-not $placa) { throw 'Nenhuma placa de rede ativa encontrada.' }

        # Remove IP automático e define IP fixo; DNS aponta para o próprio servidor
        Remove-NetIPAddress -InterfaceIndex $placa.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $placa.ifIndex -IPAddress $IP -PrefixLength $Prefixo | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $placa.ifIndex -ServerAddresses '127.0.0.1'

        Write-Host "IP $IP/$Prefixo configurado em '$($placa.Name)'."

        if ($env:COMPUTERNAME -ne $NomeServidor) {
            Rename-Computer -NewName $NomeServidor -Force
            Write-Host "Servidor renomeado para $NomeServidor. Reiniciando..."
            Restart-Computer -Force
        }
    }

    2 {
        Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
        Write-Host 'AD DS e DNS instalados. Criando a floresta...'

        $senhaDSRM = Read-Host 'Senha do modo de restauração (DSRM)' -AsSecureString

        Install-ADDSForest `
            -DomainName $Dominio `
            -DomainNetbiosName $NetBIOS `
            -InstallDns `
            -SafeModeAdministratorPassword $senhaDSRM `
            -Force
        # O servidor reinicia automaticamente ao final
    }
}
