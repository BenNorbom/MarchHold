extends RefCounted
## Protects the account file with Windows DPAPI under the current Windows user.

const PATH := "user://chatgpt_connection.bin"
const DPAPI := """
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String([Console]::ReadLine())
    $scope = [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    $output = [System.Security.Cryptography.ProtectedData]::%s($bytes, $null, $scope)
    [Console]::WriteLine([Convert]::ToBase64String($output))
} catch {
    [Console]::WriteLine('')
    exit 1
}
"""


static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var bytes := _crypt(FileAccess.get_file_as_bytes(PATH), "Unprotect")
	var saved = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
	return saved if saved is Dictionary else {}


static func write(account: Dictionary) -> bool:
	var bytes := _crypt(JSON.stringify(account).to_utf8_buffer(), "Protect")
	if bytes.is_empty():
		return false
	# Use a same-directory encrypted temporary file so replacement is atomic.
	var temp_path := PATH + "." + Crypto.new().generate_random_bytes(12).hex_encode() + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error == OK and DirAccess.rename_absolute(temp_path, PATH) == OK:
		return true
	DirAccess.remove_absolute(temp_path)
	return false


static func _crypt(bytes: PackedByteArray, method: String) -> PackedByteArray:
	if OS.get_name() != "Windows" or bytes.is_empty():
		return PackedByteArray()
	var powershell := OS.get_environment("SystemRoot") + "/System32/WindowsPowerShell/v1.0/powershell.exe"
	var command := Marshalls.raw_to_base64((DPAPI % method).to_utf16_buffer())
	var process := OS.execute_with_pipe(powershell, ["-NoProfile", "-NonInteractive", "-EncodedCommand", command])
	if process.is_empty():
		return PackedByteArray()
	var pipe: FileAccess = process["stdio"]
	pipe.store_line(Marshalls.raw_to_base64(bytes))
	return Marshalls.base64_to_raw(pipe.get_line().strip_edges())
