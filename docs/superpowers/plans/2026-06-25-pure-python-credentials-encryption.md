# Pure Python Credentials Encryption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Web backend credential encryption dependency on `cryptography` with a pure Python authenticated encryption implementation.

**Architecture:** Keep the existing `encrypt_text` and `decrypt_text` API so repository and installer code do not change. Store tokens with a `KF1.` prefix, encrypt with AES-CTR via `pyaes`, and authenticate token metadata plus ciphertext with HMAC-SHA256. Continue storing `credentials/master.key` as URL-safe base64 bytes so existing key files remain usable.

**Tech Stack:** Python 3.7, stdlib `base64`/`hashlib`/`hmac`/`secrets`, `pyaes==1.6.1`, pytest/unittest backend tests.

---

### Task 1: Credential Behavior Tests

**Files:**
- Modify: `web/backend/tests/test_credentials.py`

- [ ] **Step 1: Write failing tests**

Add tests that assert encrypted tokens use the new version prefix, encrypting the same plain text twice produces different tokens, tampered tokens fail to decrypt, and an existing Fernet-style base64 key file can still be used as key material.

- [ ] **Step 2: Run tests to verify failure**

Run: `python -m pytest web/backend/tests/test_credentials.py -q`

Expected: FAIL before implementation because tokens do not use `KF1.` and tamper handling is not implemented in the new format.

### Task 2: Pure Python Encryption Implementation

**Files:**
- Modify: `web/backend/kubefoundry/security/credentials.py`

- [ ] **Step 1: Implement key loading**

Keep `credentials/master.key`; generate 32 random bytes encoded with `base64.urlsafe_b64encode`, and decode existing base64 key files.

- [ ] **Step 2: Implement token encryption**

Use random 16-byte salt and 16-byte nonce. Derive 32-byte encryption and authentication keys from the master key and salt with SHA-256 domain separation. Encrypt UTF-8 plaintext with AES-CTR from `pyaes`.

- [ ] **Step 3: Implement token verification and decryption**

Parse `KF1.` tokens, verify HMAC-SHA256 before decrypting, and raise `ValueError("password decrypt failed")` for malformed or tampered tokens.

- [ ] **Step 4: Run credential tests**

Run: `python -m pytest web/backend/tests/test_credentials.py -q`

Expected: PASS.

### Task 3: Dependency and Packaging Verification

**Files:**
- Modify: `web/backend/requirements.txt`

- [ ] **Step 1: Replace dependency**

Remove `cryptography>=42.0.0` and add `pyaes==1.6.1`.

- [ ] **Step 2: Verify dependency intent**

Run: `rg -n "cryptography|pyaes" web/backend package.sh docs/superpowers/plans/2026-06-25-pure-python-credentials-encryption.md`

Expected: No backend runtime dependency on `cryptography`; `pyaes==1.6.1` appears in requirements and the plan.

### Task 4: Regression Tests

**Files:**
- Test: `web/backend/tests/test_credentials.py`
- Test: `web/backend/tests/test_node_login_api.py`
- Test: `scripts/tests/test_web_package_deploy.sh`

- [ ] **Step 1: Run focused backend tests**

Run: `python -m pytest web/backend/tests/test_credentials.py web/backend/tests/test_node_login_api.py -q`

Expected: PASS.

- [ ] **Step 2: Run package deploy shell test**

Run in Bash: `bash scripts/tests/test_web_package_deploy.sh`

Expected: PASS and no `cryptography` requirement assertion failure.
