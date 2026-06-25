def test_encrypt_password_is_not_plaintext(tmp_path, monkeypatch):
    monkeypatch.setenv("KF_DATA_DIR", str(tmp_path))
    from kubefoundry.security.credentials import decrypt_text, encrypt_text

    token = encrypt_text("Secret123!")
    assert token.startswith("KF1.")
    assert token != "Secret123!"
    assert decrypt_text(token) == "Secret123!"
    assert (tmp_path / "credentials" / "master.key").exists()


def test_encrypt_password_uses_random_nonce(tmp_path, monkeypatch):
    monkeypatch.setenv("KF_DATA_DIR", str(tmp_path))
    from kubefoundry.security.credentials import decrypt_text, encrypt_text

    first = encrypt_text("Secret123!")
    second = encrypt_text("Secret123!")

    assert first != second
    assert decrypt_text(first) == "Secret123!"
    assert decrypt_text(second) == "Secret123!"


def test_decrypt_rejects_tampered_token(tmp_path, monkeypatch):
    monkeypatch.setenv("KF_DATA_DIR", str(tmp_path))
    from kubefoundry.security.credentials import decrypt_text, encrypt_text

    token = encrypt_text("Secret123!")
    tampered = token[:-1] + ("A" if token[-1] != "A" else "B")

    try:
        decrypt_text(tampered)
        assert False, "tampered token should fail"
    except ValueError as exc:
        assert str(exc) == "password decrypt failed"


def test_existing_base64_master_key_is_reused(tmp_path, monkeypatch):
    monkeypatch.setenv("KF_DATA_DIR", str(tmp_path))
    credentials_dir = tmp_path / "credentials"
    credentials_dir.mkdir()
    (credentials_dir / "master.key").write_text(
        "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=\n",
        encoding="utf-8",
    )

    from kubefoundry.security.credentials import decrypt_text, encrypt_text

    token = encrypt_text("Secret123!")

    assert token.startswith("KF1.")
    assert decrypt_text(token) == "Secret123!"
