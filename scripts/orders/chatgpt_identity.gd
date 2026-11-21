extends RefCounted
## OIDC identity validation for MarchHold's public OAuth client.

const ISSUER := "https://auth.openai.com"
const SAFE_HEADER := "300d06092a864886f70d0101010500"


static func base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


static func _decode(value: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(value.replace("-", "+").replace("_", "/") + "=".repeat((4 - value.length() % 4) % 4))


static func verify(token: String, keys: Array, client: String, nonce: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() != 3:
		return {}
	var header = JSON.parse_string(_decode(parts[0]).get_string_from_utf8())
	var claims = JSON.parse_string(_decode(parts[1]).get_string_from_utf8())
	if not header is Dictionary or not claims is Dictionary or header.get("alg") != "RS256":
		return {}
	var audience = claims.get("aud")
	if audience != client and not (audience is Array and client in audience and claims.get("azp", client) == client):
		return {}
	if claims.get("iss") != ISSUER or claims.get("nonce") != nonce or str(claims.get("sub", "")) == "":
		return {}
	if float(claims.get("exp", 0)) <= Time.get_unix_time_from_system():
		return {}
	for jwk in keys:
		if jwk is Dictionary and jwk.get("kty") == "RSA" and jwk.get("kid") == header.get("kid") and jwk.has("n") and jwk.has("e"):
			var key := _rsa_key(_decode(str(jwk["n"])), _decode(str(jwk["e"])))
			var digest := (parts[0] + "." + parts[1]).sha256_buffer()
			if key != null and Crypto.new().verify(HashingContext.HASH_SHA256, digest, _decode(parts[2]), key):
				return claims
	return {}


static func _rsa_key(modulus: PackedByteArray, exponent: PackedByteArray) -> CryptoKey:
	if modulus.is_empty() or exponent.is_empty():
		return null
	var rsa := _der(0x30, _integer(modulus) + _integer(exponent))
	var spki := _der(0x30, SAFE_HEADER.hex_decode() + _der(0x03, PackedByteArray([0]) + rsa))
	var encoded := Marshalls.raw_to_base64(spki)
	var pem := "-----BEGIN PUBLIC KEY-----\n"
	for i in range(0, encoded.length(), 64):
		pem += encoded.substr(i, 64) + "\n"
	pem += "-----END PUBLIC KEY-----\n"
	var key := CryptoKey.new()
	return key if key.load_from_string(pem, true) == OK else null


static func _integer(bytes: PackedByteArray) -> PackedByteArray:
	return _der(0x02, PackedByteArray([0]) + bytes if bytes[0] >= 128 else bytes)


static func _der(tag: int, bytes: PackedByteArray) -> PackedByteArray:
	var size := bytes.size()
	if size < 128:
		return PackedByteArray([tag, size]) + bytes
	if size < 256:
		return PackedByteArray([tag, 0x81, size]) + bytes
	return PackedByteArray([tag, 0x82, size >> 8, size & 0xff]) + bytes
