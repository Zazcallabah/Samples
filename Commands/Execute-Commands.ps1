﻿<#
.SYNOPSIS
	Executes a command batch from a file and returns its result
.DESCRIPTION
	This script uses cURL to communicate with the RemoteX web services.
	It can be obtained from http://curl.haxx.se/download.html
.PARAMETER Path
	The path to the XML file with the commands to be executed
.PARAMETER ServiceUri
	The url to the web service - must end with /api
.PARAMETER Username
	The username to authenticate as
.PARAMETER Password
	The password to use for authentication
#>
param( 
	[parameter(mandatory=$true)]
	$Path,
	[parameter(mandatory=$true)]
	[ValidateScript({ $_ -imatch "^https?://.+/api/?$" })]
	$ServiceUri,
	[parameter(mandatory=$true)]
	$Username,
	[parameter(mandatory=$true)]
	$Password,
	[parameter(mandatory=$false)]
	[Switch] $noOutput
)

if( !( Get-Command curl ) ) {
	if( !(test-path ".\curl.exe") ) {
		Write-Error "Could not find curl command in the path or in local folder"
		exit 1
	} else {
		set-alias curl ".\curl.exe"
	}
}

$file = gi -ErrorAction SilentlyContinue $Path
if( !$file ) {
	Write-Error ("Could not find the file '{0}'" -f $Path)
	exit 2
}

if( $file.Extension -ne ".xml" ) {
	Write-Error ("Can only use XML files '{0}'" -f $Path)
	exit 3
}
$outputFile = "{0}\{1}_output.xml" -f $file.Directory, $file.BaseName
$traceFile = "{0}\{1}_trace.txt" -f $file.Directory, $file.BaseName

if( Test-Path $outputFile ) {
	rm -Force $outputFile
}
if( Test-path $traceFile ) {
	rm -Force $traceFile
}

$url = "{0}/commands" -f $ServiceUri.TrimEnd("/")
$cred = "{0}:{1}" -f $Username, $Password
$sw = [System.Diagnostics.Stopwatch]::StartNew()
curl -s --insecure --trace $traceFile -o $outputFile -u $cred -X POST -T $file.FullName -H 'Content-Type: application/xml' -H 'Accept: application/xml' $url
if(!$? -or !(Test-Path $outputFile)) {
	Write-Error ("Curl failed with error {0}" -f $LASTEXITCODE)
	exit 5
}
$sw.Stop()

try {
	$content = gc $outputFile
	if( $content -notmatch "<CommandBatchResponse" ) {
		throw ("Cannot find root element: {0}" -f ($content -replace "<[^>]+>",""))
	}
	$xml = ([xml]$content).CommandBatchResponse
} catch {
	Write-Error ("Error in XML: {0}" -f $_ )
	exit 4
}

Write-Host "Command batch execution took $($sw.Elapsed.Minutes)m $($sw.Elapsed.Seconds)s"
$outputErrorsOnly = $false
if($xml.HasErrors -ne "true") {
	Write-Host "Successfully executed commands:"
	$exitCode = 0
	if($DebugPreference -eq "SilentlyContinue") {
		$traceFile,$outputFile | rm
	}
} else {
	Write-Host -ForegroundColor Red "Command execution failed!"
	$noOutput = $false
	$outputErrorsOnly = $true
	$exitCode = 1
}

Write-Host ""
if( Test-Path $outputFile ) {
	Write-Host ("Response written to {0}" -f $outputFile)
}
if( Test-Path $traceFile ) {
	Write-Host ("cURL trace output written to {0}" -f $traceFile)
}

if( !$noOutput) {
	$xml.CommandResponse | ?{ !$outputErrorsOnly -or $_.HasErrors -eq "true" } | %{
		Write-Host -NoNewline "Command: "
		Write-Host -ForegroundColor Yellow $_.Command.Name
		if( $_.HasErrors -eq "true" ) {
			Write-Host -ForegroundColor Red -NoNewline "  Error: "
			Write-Host -ForegroundColor Red $_.ErrorMessage
		}
		$_.Command.Parameter | %{
			Write-Host -NoNewline "   Parameter: "
			Write-Host -ForegroundColor Yellow $_.Name
			$_.Value | %{
				Write-Host -NoNewline "       Value: "
				Write-Host -ForegroundColor Yellow $_
			}
		}
		Write-Host "Affected items: "
		$_.AffectedItems.Item | %{
			Write-Host -ForegroundColor Yellow ("   {0} (Revision: {1})" -f $_.Href, $_.Revision)
		}
		Write-Host ""
	}
}	
exit $exitCode