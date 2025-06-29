# `crypto` - Cryptographic Hashing

The `crypto` library provides a convenient interface to the hashing algorithms found in Dart's powerful `crypto` and `pointycastle` packages. It allows you to easily compute common cryptographic hashes, perform message authentication with HMAC, and use symmetric AES encryption.

## API Overview

All functions in this library take a single argument, which can be either a string or a byte sequence (a `Uint8List` from `dart.string.bytes` or a Lua table of integers). They return a lowercase hex-encoded string representing the calculated hash.

### `crypto.md5(data)`
Computes the MD5 hash of the input `data`.

**Warning**: MD5 is considered cryptographically broken and should not be used for security-sensitive applications. It is provided for interoperability with legacy systems.

### `crypto.sha1(data)`
Computes the SHA-1 hash of the input `data`.

**Warning**: SHA-1 is also considered weak and should be avoided for new security applications. It is provided for interoperability purposes.

### `crypto.sha256(data)`
Computes the SHA-256 hash of the input `data`. This is a strong, widely used hash function suitable for most security needs.

### `crypto.sha512(data)`
Computes the SHA-512 hash of the input `data`. This is another strong hash function, providing a larger hash size than SHA-256.

### `crypto.hmac(digest, key, message)`
Computes the HMAC (Hash-based Message Authentication Code) for a given `message` using a `key` and a specified hash `digest`. The digest is a string like `'SHA-256'`.

This is useful for verifying both the integrity and authenticity of a message.

### `crypto.randomBytes(count)`
Generates a specified `count` of cryptographically secure random bytes, returning them as a `Uint8List`. This is the recommended way to create keys and initialization vectors (IVs). The `count` must be between 1 and 1024.

### `crypto.aesEncrypt(key, iv, data)`
Encrypts `data` using the AES (Advanced Encryption Standard) algorithm with CBC (Cipher Block Chaining) mode and PKCS7 padding.
- `key`: The encryption key. Must be 16, 24, or 32 bytes long (for AES-128, AES-192, or AES-256).
- `iv`: The initialization vector. Must be 16 bytes long.
- `data`: The plaintext to encrypt (string or bytes).

Returns the encrypted ciphertext as a `Uint8List`.

### `crypto.aesDecrypt(key, iv, data)`
Decrypts `data` that was encrypted with `crypto.aesEncrypt`. The `key` and `iv` must be the same as those used for encryption. Returns the original plaintext as a `Uint8List`.

## Examples

### Basic Hashing

```lua
local my_data = "lualike is awesome"

-- Calculate different hashes for the same input
local md5_hash = crypto.md5(my_data)
local sha256_hash = crypto.sha256(my_data)

print("MD5: " .. md5_hash)
print("SHA256: " .. sha256_hash)

-- Example Output:
-- MD5: 8a4c8189c453883a936a10e82f143743
-- SHA256: 2b8a248a584a0d255743b23c2a033b063378417536d3c8f846f3325c27543d3a
```

### Hashing Binary Data

The crypto functions can work directly with byte sequences returned from other libraries, such as `dart.string.bytes`.

```lua
-- Get the byte representation of a string
local bytes = dart.string.bytes.toBytes("hello world")

-- Hash the bytes directly
local hash = crypto.sha256(bytes)

print("Hash of bytes: " .. hash)
-- Hash of bytes: b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
```

### HMAC Authentication

```lua
local key = "my-very-secret-key"
local message = "This message is authentic"

-- Generate the HMAC tag
local tag = crypto.hmac('SHA-256', key, message)
print("HMAC Tag: " .. tag)

-- To verify the tag, the receiver would compute the same HMAC
-- with the same key and message and check if the tags match.
```

### AES Encryption and Decryption

```lua
-- 1. Generate a secure key and initialization vector (IV)
-- AES-128 uses a 16-byte key. The IV for AES is also 16 bytes.
local key = crypto.randomBytes(16)
local iv = crypto.randomBytes(16)

-- 2. Encrypt the plaintext
local plaintext = "lualike is a secret, tell no one"
local encrypted = crypto.aesEncrypt(key, iv, plaintext)
print("Encrypted data (first 16 bytes): " .. string.sub(dart.string.bytes.fromBytes(encrypted), 1, 16))

-- 3. Decrypt the ciphertext
-- The key and IV must be the same to decrypt successfully.
local decrypted_bytes = crypto.aesDecrypt(key, iv, encrypted)
local decrypted_text = dart.string.bytes.fromBytes(decrypted_bytes)

-- 4. Verify the result
print("Decrypted text: " .. decrypted_text)
assert(plaintext == decrypted_text)

-- Example Output:
-- Encrypted data (first 16 bytes): ... (will be random bytes)
-- Decrypted text: lualike is a secret, tell no one
```