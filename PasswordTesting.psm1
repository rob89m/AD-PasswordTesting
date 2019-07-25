<#
	.DESCRIPTION
		The two functions contained in this script are used for auditing AD passwords against a list of comprimised passwords.
		A great password list to use is the NTLM lists available from https://haveibeenpwned.com/Passwords

	.NOTES
		Version:	1.0
		Author: 	Robert Taylor
		Email:  	rob89m@outlook.com
#>

Function Export-ADData
{
<#
	.DESCRIPTION
		This script will be run on the server containing the AD to be checked.
		This cmdlet creates a ShadowCopy of the Active Directory database and System Registry, stores it in the path specified until uploaded, uploads to
		specified FTPS server, and then deletes the files from the local directory
	 
	.EXAMPLE
		Export-ADData -Customer "AIT" -ExportDir "C:\ADExport\ADData" -FTPAdd "ftp://upload.cloud.com.au/" -FTPUser "FTPUser" -FTPPass "MyPassword$123"
	 
	.PARAMETER Customer
		Shortcode to internally identify the customer that the data belongs to.

	.PARAMETER ExportDir
		A path for the ShadowCopy to be stored whilst being processed for upload.

	.PARAMETER FTPAdd
		Address of the FTP server

	.PARAMETER FTPUser
		Username for the FTP

	.PARAMETER FTPPass
		Password for the FTP
#>
    [CmdletBinding()]
    Param (
        #[Parameter(Mandatory=$true)][string]$Customer,
        [Parameter(Mandatory=$true)][string]$ExportDir,
        [Parameter(Mandatory=$true)][string]$FTPAdd,
        [Parameter(Mandatory=$true)][string]$FTPUser,
        [Parameter(Mandatory=$true)][string]$FTPPass
        )
    END
    {
        # Perform ShadowCopy AD Dump
        ntdsutil "ac i ntds" "ifm" "create full $ExportDir" q q

        # Flatens files into a single directory for upload
        Get-ChildItem $ExportDir -Recurse -File | Move-Item -Destination $ExportDir
        Get-ChildItem $ExportDir -Directory | Remove-Item

        # Uploads files via FTPS
        [Net.ServicePointManager]::ServerCertificateValidationCallback={$true} 
            foreach($item in (dir $ExportDir)) 
            { 
                write-output "————————————–" 
                $fileName = $item.FullName 
                write-output $fileName 
                $ftp = [System.Net.FtpWebRequest]::Create("$FTPAdd"+"$Customer"+$item.Name) 
                $ftp = [System.Net.FtpWebRequest]$ftp 
                $ftp.UsePassive = $true 
                $ftp.UseBinary = $true 
                $ftp.EnableSsl = $true 
                $ftp.Credentials = new-object System.Net.NetworkCredential("$FTPUser","$FTPPass")
                $ftp.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile 
                $rs = $ftp.GetRequestStream() 

                $reader = New-Object System.IO.FileStream ($fileName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read) 
                [byte[]]$buffer = new-object byte[] 4096 
                [int]$count = 0 
                do 
                { 
                    $count = $reader.Read($buffer, 0, $buffer.Length) 
                    $rs.Write($buffer,0,$count) 
                } while ($count -gt 0) 
                $reader.Close() 
                $rs.Close() 
                write-output "+transfer completed"
			}
			
		# Deletes uploaded files
			$item.Delete() 
			write-output "+file deleted" 
    }
}

Function Run-PasswordTest
{
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
        if (Get-Module -ListAvailable -Name DSInternals)
			{
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
				$DB = $Uploads$Folder'\ntds.dit'
				Get-ADDBAccount -All -DBPath $DB -BootKey $key | Test-PasswordQuality -WeakPasswordsFile $DicPath | Out-File $ResultsFolder$Folder
				Write-Host "Password testing for $Folder complete"
				Write-Host "Removing $Folder AD Data export from server for security purposes"
				Get-ChildItem $Uploads$Folder | Remove-Item
			}
		}
	}
}
