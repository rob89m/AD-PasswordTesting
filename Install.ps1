$psdir = "C:\program files\WindowsPowerShell\Modules\AD-PasswordTesting\"
$url = "https://raw.githubusercontent.com/rob89m/AD-PasswordTesting/master/AD-PasswordTesting.psm1"
$output = "C:\Program Files\WindowsPowerShell\Modules\AD-PasswordTesting\AD-PasswordTesting.psm1"

# Check if PS Module directory exists and create is missing
if (!(Test-Path $psdir))
  {
    mkdir $psdir
  }

# Check if PS Module exists and delete is present
# This piece relates to users updating the module
if (Test-Path $output)
  {
    Remove-Item $output
    sleep 3
  }

# Downloads Module
Invoke-WebRequest -Uri $url -OutFile $output

# Unblocks Module to allow it to run
Unblock-File $output
