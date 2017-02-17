#
# ADFS_Install.ps1
#
Param (		
		[Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [string]$Username,

	    [Parameter(Mandatory)]
        [string]$Password,

		[Parameter(Mandatory)]
        [string]$Share,

		[Parameter(Mandatory)]
        [string]$sasToken,

		[Parameter(Mandatory)]
        [string]$StsServiceName,

		[Parameter(Mandatory)]
        [string]$CertPassword,

		[Parameter(Mandatory)]
        [string]$CAComputerName,
		[Parameter(Mandatory)]
        [string]$PublicCert

       )

$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$DomainCreds = New-Object PSCredential ("$DomainName\$Username", $SecurePassword)
$SecureCertPassword = ConvertTo-SecureString -String $CertPassword -AsPlainText -Force
$User=$Share
$Share="\\"+$Share+".file.core.windows.net\skype"
$PublicCertbool= [System.Convert]::ToBoolean($PublicCert)

# ADFS Install
Add-WindowsFeature ADFS-Federation -IncludeManagementTools

# Enabling remote powershell + CredSSP as KDSRootkey command need a Cred SSP session to process
Enable-PSRemoting
Enable-WSManCredSSP -Role client -DelegateComputer * -force
Enable-WSManCredSSP -Role server -force
	
#Invoke-Command  -Credential $DomainCreds -ComputerName $env:COMPUTERNAME -ScriptBlock {
Invoke-Command  -Credential $DomainCreds -Authentication CredSSP -ComputerName $env:COMPUTERNAME -ScriptBlock {
 
	# Working variables
     param (
        $workingDir,
        $_Share,
        $_User,
        $_sasToken,
		$_certPassword,
		$_stsServiceName,
		$_DomainCreds,
		$_DomainName,
		$_CAComputerName,
		$_PublicCert
    )

    #connect to file share on storage account
    net use G: $_Share /u:$_User $_sasToken
    
    #go to our packages scripts folder
    Set-Location $workingDir


    
	if ($_PublicCert) {
		#Import STS service root CA   
		$RootCAfilepath = "G:\cert\STS_RootCA.crt"
		Import-Certificate -Filepath (get-childitem $RootCAfilepath) -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Continue

		#install the certificate that will be used for ADFS Service
		$STScert = 'G:\cert\sts.'+$_DomainName+'.pfx'
		Import-PfxCertificate -Exportable -Password $_certPassword -CertStoreLocation cert:\localmachine\my -FilePath $STScert  
	}
	else {
		
		# Private CA for Online Request
		$CertificateAuthority = $_CAComputerName+'.'+$_DomainName+'\'+$_DomainName+'-CA'
	
		Import-Module .\NewCertReq.ps1
		# Request Web Application Proxy certificate
		New-CertificateRequest -subject $_stsServiceName -OnlineCA $CertificateAuthority
  	}   
	 
	#get thumbprint of certificate
	#$cert = Get-ChildItem -Path Cert:\LocalMachine\my | ?{$_.Subject -eq "CN=$_stsServiceName, OU=Free SSL, OU=Domain Control Validated"} 
	$certificateThumbprint = (get-childitem Cert:\LocalMachine\My | where {$_.subject -eq "CN="+$_stsServiceName} | Sort-Object -Descending NotBefore)[0].thumbprint
 
	$STScert = 'G:\share\sts.'+$_DomainName+'.pfx'
    Export-pfxCertificate -Cert (get-childitem Cert:\LocalMachine\My | where {$_.subject -like $_stsServiceName}) -FilePath $STScert -Password $_certPassword -Force

	#Configure ADFS Farm
    Import-Module ADFS
 
	Install-AdfsFarm -CertificateThumbprint $certificateThumbprint -FederationServiceName $_stsServiceName -Credential $_DomainCreds `
	 -FederationServiceDisplayName "SFBlab AD Federation Service" -ServiceAccountCredential $_DomainCreds -OverwriteConfiguration 

	#Remove installation file Drive
	net use G: /d

	#Pin shortcuts to taskbar
   $sa = new-object -c shell.application
   $pn = $sa.namespace("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools").parsename('Windows PowerShell ISE.lnk')
   $pn.invokeverb('taskbarpin')

} -ArgumentList $PSScriptRoot, $Share, $User, $sasToken, $SecureCertPassword, $StsServiceName, $DomainCreds, $DomainName, $CAComputerName, $PublicCertbool


Disable-PSRemoting
Disable-WSManCredSSP -role client
Disable-WSManCredSSP -role server
Restart-Computer