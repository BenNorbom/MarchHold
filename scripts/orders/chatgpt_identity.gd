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
	if not header is Dictionary or not claims is Dictionary or not is_same(header.get("alg"), "RS256"):
		return {}
	var audience = claims.get("aud")
	if not is_same(audience, client) and not (audience is Array and client in audience and is_same(claims.get("azp", client), client)):
		return {}
	var subject = claims.get("sub")
	if not is_same(claims.get("iss"), ISSUER) or not is_same(claims.get("nonce"), nonce) or not subject is String or subject.is_empty():
		return {}
	var expires = claims.get("exp")
	if not (expires is float or expires is int) or expires <= Time.get_unix_time_from_system():
		return {}
	var key_id = header.get("kid")
	if not key_id is String or key_id.is_empty():
		return {}
	for jwk in keys:
		if jwk is Dictionary and is_same(jwk.get("kty"), "RSA") and is_same(jwk.get("kid"), key_id) and jwk.get("n") is String and jwk.get("e") is String:
			var key := _rsa_key(_decode(jwk["n"]), _decode(jwk["e"]))
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
