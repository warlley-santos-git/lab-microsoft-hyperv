<#
.SYNOPSIS
    Ingressa a VM CLI01 no domínio do laboratório.

.DESCRIPTION
    Executar DENTRO da CLI01, como Administrador local.
    A CLI01 recebe IP do DHCP da DC01. O script confere a conectividade,
    renomeia a máquina e ingressa no domínio.

.EXAMPLE
    .\04-Ingressar-Cliente.ps1 -Dominio lab.local
#>
[CmdletBinding()]
param(
    [string]$Dominio   = 'lab.local',
    [string]$NovoNome  = 'CLI01',
    [string]$IPDC      = '192.168.100.10'
)

#Requires -RunAsAdministrator

Write-Host 'Renovando IP pelo DHCP...'
ipconfig /renew | Out-Null

if (-not (Test-Connection -ComputerName $IPDC -Count 2 -Quiet)) {
    throw "Não foi possível alcançar o DC ($IPDC). Verifique se as duas VMs estão no switch LAB-Interno."
}

try {
    Resolve-DnsName $Dominio -ErrorAction Stop | Out-Null
} catch {
    throw "O DNS não resolveu '$Dominio'. Confira se o DHCP entregou o DNS $IPDC (ipconfig /all)."
}

$credencial = Get-Credential -Message "Usuário com permissão no domínio (ex.: LAB\Administrator)"

$params = @{
    DomainName = $Dominio
    Credential = $credencial
    Restart    = $true
    Force      = $true
}
if ($env:COMPUTERNAME -ne $NovoNome) { $params.NewName = $NovoNome }

Add-Computer @params
