import os
import re
import warnings

warnings.filterwarnings("ignore", message="Python 3.7 is no longer supported.*")
from cryptography.fernet import Fernet, InvalidToken

from kubefoundry.store.db import data_dir


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
        key = Fernet.generate_key()
        with open(path, "wb") as fh:
            fh.write(key)
        _chmod(path, 0o600)
        return key
    _ensure_private_file(path)
    with open(path, "rb") as fh:
        key = fh.read().strip()
    if not key:
        raise ValueError("master key is empty")
    return key


def encrypt_text(plain):
    if not plain:
        return ""
    token = Fernet(load_master_key()).encrypt(str(plain).encode("utf-8"))
    return token.decode("utf-8")


def decrypt_text(token):
    if not token:
        return ""
    try:
        return Fernet(load_master_key()).decrypt(str(token).encode("utf-8")).decode("utf-8")
    except InvalidToken:
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
