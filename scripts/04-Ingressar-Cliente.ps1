<#
.SYNOPSIS
    Ingressa a VM CLI01 no domínio do laboratório.

.DESCRIPTION
    Executar DENTRO da CLI01, como Administrador local.
    A CLI01 recebe IP do DHCP da DC01. Antes de ingressar, o script confere:
      1. Se a placa de rede recebeu IP do DHCP (e não um IP 169.254.x.x)
      2. Se o DNS resolve o domínio
      3. Se a porta LDAP (389) do DC responde

    Não usa ping: o Windows Server bloqueia ping por padrão no firewall.

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

# 1. IP recebido do DHCP
Write-Host 'Renovando IP pelo DHCP...'
ipconfig /release | Out-Null
ipconfig /renew   | Out-Null

$ip = Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -notlike '127.*' } |
      Select-Object -First 1

if (-not $ip -or $ip.IPAddress -like '169.254.*') {
    throw @"
A CLI01 não recebeu IP do DHCP (IP atual: $($ip.IPAddress)).
Verifique:
  - No host: Get-VMNetworkAdapter -VMName DC01, CLI01  (as duas no switch LAB-Interno?)
  - Na DC01: Get-DhcpServerv4Scope                      (escopo Active?)
  - Na DC01: Get-DhcpServerInDC                         (DHCP autorizado?)
"@
}
Write-Host "IP recebido: $($ip.IPAddress)" -ForegroundColor Green

# 2. DNS resolve o domínio
try {
    Resolve-DnsName $Dominio -ErrorAction Stop | Out-Null
    Write-Host "DNS resolve '$Dominio'." -ForegroundColor Green
} catch {
    throw "O DNS não resolveu '$Dominio'. Confira se o DHCP entregou o DNS $IPDC (ipconfig /all)."
}

# 3. Porta LDAP do controlador de domínio
$ldap = Test-NetConnection -ComputerName $IPDC -Port 389 -WarningAction SilentlyContinue
if (-not $ldap.TcpTestSucceeded) {
    throw "O DC ($IPDC) não respondeu na porta 389 (LDAP). Confira se a DC01 está ligada e o AD está funcionando."
}
Write-Host "DC respondendo na porta 389 (LDAP)." -ForegroundColor Green

# 4. Ingressar no domínio
$credencial = Get-Credential -Message "Usuário com permissão no domínio (ex.: LAB\Administrator)"

$params = @{
    DomainName = $Dominio
    Credential = $credencial
    Restart    = $true
    Force      = $true
}

# Renomear e ingressar ao mesmo tempo (Add-Computer -NewName) pode falhar com
# "The directory service is busy". O caminho mais estável: renomear localmente
# primeiro e ingressar já com o nome novo (JoinWithNewName).
if ($env:COMPUTERNAME -ne $NovoNome) {
    Rename-Computer -NewName $NovoNome -Force -WarningAction SilentlyContinue
    $params.Options = 'JoinWithNewName'
    Write-Host "Computador renomeado para $NovoNome (vale após o reinício)."
}

Add-Computer @params
