def test_encrypt_password_is_not_plaintext(tmp_path, monkeypatch):
    monkeypatch.setenv("KF_DATA_DIR", str(tmp_path))
    from kubefoundry.security.credentials import decrypt_text, encrypt_text

    token = encrypt_text("Secret123!")
    assert token != "Secret123!"
    assert decrypt_text(token) == "Secret123!"
    assert (tmp_path / "credentials" / "master.key").exists()
