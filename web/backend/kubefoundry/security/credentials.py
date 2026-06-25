import base64
import hashlib
import hmac
import os
import re
import secrets

import pyaes

from kubefoundry.store.db import data_dir


TOKEN_PREFIX = "KF1."
SALT_SIZE = 16
NONCE_SIZE = 16
KEY_SIZE = 32
TAG_SIZE = 32
ENC_DOMAIN = b"KubeFoundry credentials encryption"
MAC_DOMAIN = b"KubeFoundry credentials authentication"


def credentials_dir():
    path = os.path.join(data_dir(), "credentials")
    if not os.path.exists(path):
        os.makedirs(path)
    _chmod(path, 0o700)
    return path


def master_key_path():
    return os.path.join(credentials_dir(), "master.key")


def load_master_key():
    path = master_key_path()
    if not os.path.exists(path):
        key = base64.urlsafe_b64encode(secrets.token_bytes(KEY_SIZE))
        with open(path, "wb") as fh:
            fh.write(key)
        _chmod(path, 0o600)
        return _decode_master_key(key)
    _ensure_private_file(path)
    with open(path, "rb") as fh:
        stored_key = fh.read().strip()
    if not stored_key:
        raise ValueError("master key is empty")
    return _decode_master_key(stored_key)


def encrypt_text(plain):
    if not plain:
        return ""
    salt = secrets.token_bytes(SALT_SIZE)
    nonce = secrets.token_bytes(NONCE_SIZE)
    enc_key, mac_key = _derive_keys(load_master_key(), salt)
    cipher = pyaes.AESModeOfOperationCTR(
        enc_key,
        counter=pyaes.Counter(initial_value=int.from_bytes(nonce, "big")),
    )
    ciphertext = cipher.encrypt(str(plain).encode("utf-8"))
    body = salt + nonce + ciphertext
    tag = hmac.new(mac_key, TOKEN_PREFIX.encode("ascii") + body, hashlib.sha256).digest()
    return TOKEN_PREFIX + _urlsafe_b64encode(body + tag)


def decrypt_text(token):
    if not token:
        return ""
    try:
        value = str(token)
        if not value.startswith(TOKEN_PREFIX):
            raise ValueError
        payload = _urlsafe_b64decode(value[len(TOKEN_PREFIX):])
        if len(payload) <= SALT_SIZE + NONCE_SIZE + TAG_SIZE:
            raise ValueError
        body = payload[:-TAG_SIZE]
        tag = payload[-TAG_SIZE:]
        salt = body[:SALT_SIZE]
        nonce = body[SALT_SIZE:SALT_SIZE + NONCE_SIZE]
        ciphertext = body[SALT_SIZE + NONCE_SIZE:]
        enc_key, mac_key = _derive_keys(load_master_key(), salt)
        expected_tag = hmac.new(
            mac_key,
            TOKEN_PREFIX.encode("ascii") + body,
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(tag, expected_tag):
            raise ValueError
        cipher = pyaes.AESModeOfOperationCTR(
            enc_key,
            counter=pyaes.Counter(initial_value=int.from_bytes(nonce, "big")),
        )
        return cipher.decrypt(ciphertext).decode("utf-8")
    except Exception:
        raise ValueError("password decrypt failed")


def redact_sensitive(text):
    value = str(text or "")
    patterns = [
        (r"SSHPASS=([^\s]+)", "SSHPASS=***"),
        (r"(?i)(password|passwd|pwd)=([^\s]+)", r"\1=***"),
    ]
    for pattern, replacement in patterns:
        value = re.sub(pattern, replacement, value)
    return value


def _ensure_private_file(path):
    if os.name == "nt":
        return
    mode = os.stat(path).st_mode & 0o777
    if mode & 0o077:
        raise ValueError("master key permissions are too open")


def _chmod(path, mode):
    try:
        os.chmod(path, mode)
    except OSError:
        pass


def _decode_master_key(stored_key):
    try:
        key = _urlsafe_b64decode(stored_key.decode("ascii"))
    except (AttributeError, TypeError, ValueError):
        key = bytes(stored_key)
    if len(key) < KEY_SIZE:
        key = hashlib.sha256(key).digest()
    return key[:KEY_SIZE]


def _derive_keys(master_key, salt):
    enc_key = hashlib.sha256(ENC_DOMAIN + b"\0" + master_key + salt).digest()
    mac_key = hashlib.sha256(MAC_DOMAIN + b"\0" + master_key + salt).digest()
    return enc_key, mac_key


def _urlsafe_b64encode(value):
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _urlsafe_b64decode(value):
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))
