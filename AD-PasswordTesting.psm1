<#
	.DESCRIPTION
		The two functions contained in this script are used for auditing AD passwords against a list of comprimised passwords.
		A great password list to use is the NTLM lists available from https://haveibeenpwned.com/Passwords

	.NOTES
		Version:	1.2
		Author: 	Robert Taylor
		Email:  	rob89m@outlook.com
#>

Function Export-ADData{
	<#
		.DESCRIPTION
			This script will be run on the server containing the AD to be checked.
			This cmdlet creates a ShadowCopy of the Active Directory database and System Registry, stores it in the path specified until uploaded, uploads to
			specified FTPS server, and then deletes the files from the local directory
		 
		.EXAMPLE
			Export-ADData -Customer "AIT" -FTPAdd "upload.cloud.com.au" -FTPUser "FTPUser" -FTPPass "MyPassword$123"
		 
		.PARAMETER Customer
			Shortcode to internally identify the customer that the data belongs to.

		.PARAMETER FTPAdd
			Address of the FTP server

		.PARAMETER FTPUser
			Username for the FTP

		.PARAMETER FTPPass
			Password for the FTP
	#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Customer,
        [Parameter(Mandatory=$true)][string]$FTPAdd,
        [Parameter(Mandatory=$true)][string]$FTPUser,
        [Parameter(Mandatory=$true)][string]$FTPPass
        )
    END{
        $ExportDir = "C:\Temp\ADExport"
        mkdir $ExportDir
        
        # Perform ShadowCopy AD Dump
        ntdsutil "ac i ntds" "ifm" "create full $ExportDir" q q

        # Flatens files into a single directory for upload
        Get-ChildItem $ExportDir -Recurse -File | Move-Item -Destination $ExportDir
        Get-ChildItem $ExportDir -Directory | Remove-Item

        # Create Customer folder in FTP
		$ftprequest = [System.Net.FtpWebRequest]::Create("ftp://"+$FTPAdd+"/"+$Customer);
		$ftprequest.UsePassive = $true
		$ftprequest.UseBinary = $true
		$ftprequest.EnableSsl = $true
		$ftprequest.Credentials = New-Object System.Net.NetworkCredential($FTPUser,$FTPPass)
		$ftprequest.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
		$response = $ftprequest.GetResponse();
		Write-Host Create Folder Complete, status $response.StatusDescription
		$response.Close();
		
		# Uploads files via FTPS
		foreach($item in (dir $ExportDir)){
            $path = $item.FullName
            $fileContents = Get-Content $path -encoding byte
            $ftprequest.ContentLength = $fileContents.Length;
            $ftprequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile;
	    $requestStream = $ftprequest.GetRequestStream();
            $requestStream.Write($fileContents, 0, $fileContents.Length);
            $requestStream.Close();
            $response = $ftprequest.GetResponse();
            Write-Host Upload File Complete, status $response.StatusDescription
            $response.Close();
        }
		
		Remove-Item -Path $ExportDir -Force -Recurse
    }
}

Function Run-PasswordTest{
	<#
		.DESCRIPTION
			This script will be run on the server processing the AD Exports.
			Results are saved with the name specified in the same location that the current AD export exists
			Requires that the DSInternals suite is installed (Install-Module -Name DSInternals -Force), script will check if it exists and install automatically if missing
		 
		.EXAMPLE
			Run-PasswordTest -UploadDir "C:\FTPUpload" -DicPath C:\Temp\mypasswordlist.txt -ResultsFolder "C:\Results\Customers"
		 
		.PARAMETER UploadDirDir
			A path to were the customers exported AD data is currently located.

			ntds.dit and SYSTEM files need to be in the same folder

		.PARAMETER DicPath
			Path to the dictionary list containing passwords to test against customer AD export

		.PARAMETER ResultsFolder
			Path to where you'd like the results to be saved to.
			Results will be in sub-folders with Customers name

		.INPUTS
			Customers exported AD NTDS.dit and System Registry files
		 
		.OUTPUTS
			Report detailing current password issues
	#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$ExportDir,
        [Parameter(Mandatory=$true)][string]$DicPath,
        [Parameter(Mandatory=$true)][string]$ResultsPath
       )
    END
    
	{
        if (Get-Module -ListAvailable -Name DSInternals){
			Write-Host "DSInternals Module exists"
			Write-Host "Proceeding to password test"
		}else{
			Write-Host "DSInternals Module missing"
			Write-Host "Downloading DSInternals Module"
			Install-Module -Name DSInternals -Force
			Write-Host "Proceeding to password test"
		}
		
		

		$Folders = Get-ChildItem -Path $UploadDir -Directory
		
		$Count = $Folders | Measure-Object
		
		if ($Count.count -eq 0){
			Write-Host "No Customer AD uploads to process"
		}else{
			foreach ($Folder in $Folders){
				$key = Get-BootKey -SystemHivePath $Uploads$Folder'\SYSTEM'
				$DB = $Uploads+$Folder+'\ntds.dit'
				Get-ADDBAccount -All -DBPath $DB -BootKey $key | Test-PasswordQuality -WeakPasswordsFile $DicPath | Out-File $ResultsFolder$Folder
				Write-Host "Password testing for $Folder complete"
				Write-Host "Removing $Folder AD Data export from server for security purposes"
				Get-ChildItem $Uploads$Folder | Remove-Item
			}
		}
	}
}
