if ($Env:RuntimeName -ne "node") {
	echo "Runtime '$runtime' is not supported."
	exit 0
}

class Test
{
	[ValidateNotNullOrEmpty()][string]$Category
	[ValidateNotNullOrEmpty()][string]$Name
	[ValidateNotNullOrEmpty()][string]$File
	
	Test([string]$c, [string]$n, [string]$f) {
		$this.Category = $c
		$this.Name = $n
		$this.File = $f
	}
	
	[string]DisplayName() {
		return ("{0}/{1}" -f $this.Category, $this.Name)
	}
}
[Test[]]$Tests = @()

$Root = (Resolve-Path .\).Path
[string[]]$CategoryBlacklist = "helpers", "tools"
$TestRuns = 10

# Detect Test Categories
$Categories = Get-ChildItem -Path $Root/tests/ -Name -Directory
ForEach($Category in $Categories) {
	$skip = $false
	ForEach($CatBl in $CategoryBlacklist) {
		If ($CatBl -eq $Category) {
			$skip = $true
		}
	}
	If ($skip -eq $true) {
		continue
	}

	echo "Category '$Category'..."
	# Detect Tests
	$Files = Get-ChildItem -Path $Root/tests/$Category/ -Filter *.js -Name -File
	ForEach($File in $Files) {
		# Convert File Name to proper name by stripping .js from it.
		$Name = $File.Substring(0, $File.length - 3)
		
		# Store Test for later use.
		$Test = [Test]::new($Category, $Name, "$Root/tests/$Category/$File")
		$Tests += $Test
		
		# Register to AppVeyor
		Add-AppveyorTest -Name $Test.DisplayName() -Framework "Powershell" -FileName $Test.File
		
		echo "    Test '$Name' registered."
	}
}

# Run Tests
$ErrorCode = 0
ForEach($Test in $Tests) {
	echo ("Running Test '{0}'..." -f $Test.DisplayName())
	
	# Set AppVeyor Status
	Update-AppveyorTest -Name $Test.DisplayName() -Framework "Powershell" -FileName $Test.File -Outcome Running
	
	# Variable Storage
	$stat_total_count = $TestRuns
	$stat_error_count = 0
	$stat_time = 0
	$stat_output = ""
	$stat_error = ""
	$safe_output = ""
	$safe_error = ""
	$errmsg = ""
	$stat_outcome = ""
	
	# Run 10 Iterations
	For ($i = 0; $i -lt $stat_total_count; $i++) {
		$sw = [Diagnostics.Stopwatch]::StartNew()
		$proc = Start-Process -File "node.exe" -ArgumentList ("`"{0}`"" -f $Test.File) -RedirectStandardOutput stdout.log -RedirectStandardError stderr.log -Wait -PassThru -NoNewWindow
		$sw.Stop()
		
		$stat_time += $sw.Elapsed.TotalMilliseconds
		if ($proc.ExitCode -ne 0) {
			$stat_output = Get-Content -Path stdout.log -Force -Raw -ReadCount 0
			$stat_error = Get-Content -Path stderr.log -Force -Raw -ReadCount 0
			$stat_error_count += 1
		} elseif ($stat_error_count -eq 0) {
			$stat_output = Get-Content -Path stdout.log -Force -Raw -ReadCount 0
			$stat_error = Get-Content -Path stderr.log -Force -Raw -ReadCount 0
		}
	}
			
	# Sanitize stdout/stderr.
	if ($stat_output) {
		$safe_output = ("{0}" -f $stat_output)
	}
	if ($stat_error) {
		$safe_error = ("{0}" -f $stat_error)
	}
	
	# Set AppVeyor Info
	$stat_outcome = "Failed"	
	if ($stat_error_count -eq 0) {
		$stat_outcome = "Passed"
	} elseif ($stat_error_count -eq $stat_total_count) {
		$stat_outcome = "Failed"
		$ErrorCode = 1
	} else {
		$stat_outcome = "Inconclusive"
		$errmsg = ("{0} out of {1} tests failed." -f $stat_error_count, $stat_total_count)
		$ErrorCode = 1
	}
	
	$body = @{
		testName = $Test.DisplayName()
		testFramework = "Powershell"
		fileName = $Test.File
		durationMilliseconds = $stat_time
		outcome = $stat_outcome
		ErrorMessage = $errmsg
		ErrorStackTrace = ""
		StdOut = $safe_output
		StdErr = $safe_error
	}
	$body_json = $body | ConvertTo-Json -Compress
	Invoke-RestMethod -Method Put -Uri ("{0}api/tests" -f $Env:APPVEYOR_API_URL) -Body $body_json
}

exit $ErrorCode