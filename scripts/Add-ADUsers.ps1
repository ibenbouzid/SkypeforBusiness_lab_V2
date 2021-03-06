#
# Add-NewADUsers.ps1
#
<# Custom Script for Windows #>
Param (		

	    [Parameter(Mandatory)]
        [string]$Password,
	    [Parameter(Mandatory)]
        [string]$Share,
		[Parameter(Mandatory)]
        [string]$sasToken,
		[Parameter(Mandatory)]
        [string]$DNSName1,
		[Parameter(Mandatory)]
        [string]$DNSIPrecord1,
		[Parameter(Mandatory)]
        [string]$DNSName2,
		[Parameter(Mandatory)]
        [string]$DNSIPrecord2,
		[Parameter(Mandatory)]
        [string]$DNSName3,
		[Parameter(Mandatory)]
        [string]$DNSIPrecord3
       )
$Domain = Get-ADDomain
$DomainDNSName = $Domain.DNSRoot
$OrgUnit = "SfBusers"
$Container = "ou="+$OrgUnit+","+$Domain.DistinguishedName

New-ADOrganizationalUnit -Name $OrgUnit -Path $Domain.DistinguishedName

Import-Csv .\New-ADUsers.csv | ForEach-Object {
    $userPrinc = $_.LogonUsername+"@"+$DomainDNSName
    New-ADUser -Name $_.Name `
    -SamAccountName $_.LogonUsername `
    -UserPrincipalName $userPrinc `
	-DisplayName $_.Name `
	-GivenName $_.FirstName `
    -SurName $_.LastName `
	-Description $_.Site `
	-Department $_.Dept `
    -Path $Container `
    -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -force) `
	-Enabled $True `
	-PasswordNeverExpires $True `
    -PassThru
}



#Add DNS records for servers in DMZ and for ADFS service
Add-DnsServerResourceRecordA -IPv4Address $DNSIPrecord2 -Name $DNSName2 -ZoneName $DomainDNSName -ErrorAction Continue
Add-DnsServerResourceRecordA -IPv4Address $DNSIPrecord3 -Name $DNSName3 -ZoneName $DomainDNSName -ErrorAction Continue

#Add STS DNS record if in the same doamin otherwise create a new primary zone
$STSname = $DNSname1.split('.')[0]
$STSdomainName = $DNSname1.split('.')[1] +'.'+$DNSname1.split('.')[2]
if ($STSdomainName -match $DomainDNSName) {
	Add-DnsServerResourceRecordA -IPv4Address $DNSIPrecord1 -Name $STSname -ZoneName $DomainDNSName -ErrorAction Continue
	}
else{
	Add-DnsServerPrimaryZone -Name $STSdomainName -ReplicationScope Domain -ErrorAction Continue
	Add-DnsServerResourceRecordA -IPv4Address $DNSIPrecord1 -Name $STSname -ZoneName $STSdomainName -ErrorAction Continue
	}

#Export the root CA
$User=$Share
$Share="\\"+$Share+".file.core.windows.net\skype"
$RootCA= "G:\Share\"+$DomainDNSName+"-CA.crt"
$CAName= "CN="+$DomainDNSName+"-CA*"

net use G: $Share /u:$User $sasToken
Remove-Item $RootCA -ErrorAction SilentlyContinue
Export-Certificate -Cert (get-childitem Cert:\LocalMachine\My | where {$_.subject -like $CAName}) -FilePath $RootCA

#Install AADConnect
#Start-Process -FilePath msiexec -ArgumentList /i, "G:\AzureADConnect.msi", /quiet -Wait
Copy-Item -Path "G:\AzureADConnect.msi" -Destination "C:\AzureADConnect.msi" -ErrorAction Continue

net use G: /d