<#
.SYNOPSIS
    Configura DHCP, OUs e grupos básicos no domínio do laboratório.

.DESCRIPTION
    Executar DENTRO da DC01 depois que ela virou controlador de domínio.
      - Instala e autoriza o DHCP no AD
      - Cria o escopo 192.168.100.100-200 com gateway, DNS e domínio
      - Cria uma reserva de exemplo
      - Cria a estrutura de OUs e grupos usada pelo projeto ad-automation-powershell

.EXAMPLE
    .\03-Configurar-DHCP-OUs.ps1
#>
[CmdletBinding()]
param(
    [string]$Dominio      = 'lab.local',
    [string]$IPServidor   = '192.168.100.10',
    [string]$Rede         = '192.168.100.0',
    [string]$InicioEscopo = '192.168.100.100',
    [string]$FimEscopo    = '192.168.100.200',
    [string]$Mascara      = '255.255.255.0',
    [string]$Gateway      = '192.168.100.1'
)

#Requires -RunAsAdministrator
Import-Module ActiveDirectory

# ---------- DHCP ----------
Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null

$fqdn = "$env:COMPUTERNAME.$Dominio"
if (-not (Get-DhcpServerInDC | Where-Object DnsName -eq $fqdn)) {
    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $IPServidor
}

# Remove o aviso de "configuração pós-instalação pendente" no Server Manager
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

if (-not (Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object ScopeId -eq $Rede)) {
    Add-DhcpServerv4Scope -Name 'LAB-Clientes' -StartRange $InicioEscopo -EndRange $FimEscopo `
        -SubnetMask $Mascara -LeaseDuration (New-TimeSpan -Days 8) -State Active
}

Set-DhcpServerv4OptionValue -ScopeId $Rede -Router $Gateway -DnsServer $IPServidor -DnsDomain $Dominio

# Reserva de exemplo (troque o MAC pelo da sua impressora/VM)
$mac = '00-15-5D-00-00-50'
if (-not (Get-DhcpServerv4Reservation -ScopeId $Rede -ErrorAction SilentlyContinue | Where-Object ClientId -eq $mac)) {
    Add-DhcpServerv4Reservation -ScopeId $Rede -IPAddress '192.168.100.50' -ClientId $mac -Name 'IMPRESSORA-01' `
        -Description 'Reserva de exemplo'
}

Write-Host 'DHCP configurado.'

# ---------- OUs e grupos ----------
$raizDominio = (Get-ADDomain).DistinguishedName

function New-OUSeNaoExistir([string]$Nome, [string]$Caminho) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Nome'" -SearchBase $Caminho -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Nome -Path $Caminho -ProtectedFromAccidentalDeletion $true
    }
}

New-OUSeNaoExistir 'Usuarios'    $raizDominio
New-OUSeNaoExistir 'Grupos'      $raizDominio
New-OUSeNaoExistir 'Computadores' $raizDominio
New-OUSeNaoExistir 'Inativos'    $raizDominio

$ouUsuarios = "OU=Usuarios,$raizDominio"
$ouGrupos   = "OU=Grupos,$raizDominio"

foreach ($depto in 'Financeiro','TI','RH','Operacoes') {
    New-OUSeNaoExistir $depto $ouUsuarios
    $grupo = "GG_$depto"
    if (-not (Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $grupo -GroupScope Global -GroupCategory Security -Path $ouGrupos
    }
}

if (-not (Get-ADGroup -Filter "Name -eq 'GG_VPN'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name 'GG_VPN' -GroupScope Global -GroupCategory Security -Path $ouGrupos
}

# Novos computadores entram na OU Computadores
redircmp "OU=Computadores,$raizDominio" | Out-Null

Write-Host 'OUs e grupos criados. Laboratório pronto para ingressar o CLI01 no domínio.'
