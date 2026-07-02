function Read-YeshSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt
    )

    # Masked input so the token is not echoed to the screen. The value is written
    # to .env in plaintext (the tool reads it plainly), but masking avoids
    # shoulder-surfing during entry.
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
