"""Secure password handling for installation."""
import hashlib
import logging
import os
import struct
import subprocess

logger = logging.getLogger("greenwayos.install")

# ---------------------------------------------------------------------------
# Pure-stdlib SHA-512 crypt(3) compatible hash  ($6$salt$hash)
# Replaces the removed `crypt` module (dropped in Python 3.13).
# Algorithm: https://www.akkadia.org/docs/sha-crypt.txt
# ---------------------------------------------------------------------------

_ITOA64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"


def _to64(value: int, n: int) -> str:
    result = []
    for _ in range(n):
        result.append(_ITOA64[value & 0x3F])
        value >>= 6
    return "".join(result)


def _sha512_crypt(password: str, salt: str, rounds: int = 5000) -> str:
    """Return a $6$… shadow-compatible hash string."""
    pwd = password.encode()
    s = salt.encode()

    # Steps follow the SHA-crypt spec (sha512 variant).
    digest_b = hashlib.sha512(pwd + s + pwd).digest()

    ctx_a = hashlib.sha512(pwd + s)
    for i in range(len(pwd), 0, -64):
        ctx_a.update(digest_b if i > 64 else digest_b[:i])
    n = len(pwd)
    while n:
        ctx_a.update(digest_b if n & 1 else pwd)
        n >>= 1
    digest_a = ctx_a.digest()

    ctx_p = hashlib.sha512()
    for _ in range(len(pwd)):
        ctx_p.update(pwd)
    p_bytes_full = ctx_p.digest()
    p_str = (p_bytes_full * ((len(pwd) // 64) + 1))[:len(pwd)]

    ctx_s = hashlib.sha512()
    for _ in range(16 + digest_a[0]):
        ctx_s.update(s)
    s_bytes_full = ctx_s.digest()
    s_str = (s_bytes_full * ((len(s) // 64) + 1))[:len(s)]

    c = digest_a
    for i in range(rounds):
        ctx_c = hashlib.sha512()
        if i & 1:
            ctx_c.update(p_str)
        else:
            ctx_c.update(c)
        if i % 3:
            ctx_c.update(s_str)
        if i % 7:
            ctx_c.update(p_str)
        if i & 1:
            ctx_c.update(c)
        else:
            ctx_c.update(p_str)
        c = ctx_c.digest()

    # Permute output bytes into the crypt(3) order.
    b = c
    hashed = (
        _to64((b[0] << 16) | (b[21] << 8) | b[42], 4)
        + _to64((b[22] << 16) | (b[43] << 8) | b[1], 4)
        + _to64((b[44] << 16) | (b[2] << 8) | b[23], 4)
        + _to64((b[3] << 16) | (b[24] << 8) | b[45], 4)
        + _to64((b[25] << 16) | (b[46] << 8) | b[4], 4)
        + _to64((b[47] << 16) | (b[5] << 8) | b[26], 4)
        + _to64((b[6] << 16) | (b[27] << 8) | b[48], 4)
        + _to64((b[28] << 16) | (b[49] << 8) | b[7], 4)
        + _to64((b[50] << 16) | (b[8] << 8) | b[29], 4)
        + _to64((b[9] << 16) | (b[30] << 8) | b[51], 4)
        + _to64((b[31] << 16) | (b[52] << 8) | b[10], 4)
        + _to64((b[53] << 16) | (b[11] << 8) | b[32], 4)
        + _to64((b[12] << 16) | (b[33] << 8) | b[54], 4)
        + _to64((b[34] << 16) | (b[55] << 8) | b[13], 4)
        + _to64((b[56] << 16) | (b[14] << 8) | b[35], 4)
        + _to64((b[15] << 16) | (b[36] << 8) | b[57], 4)
        + _to64((b[37] << 16) | (b[58] << 8) | b[16], 4)
        + _to64((b[59] << 16) | (b[17] << 8) | b[38], 4)
        + _to64((b[18] << 16) | (b[39] << 8) | b[60], 4)
        + _to64((b[40] << 16) | (b[61] << 8) | b[19], 4)
        + _to64((b[62] << 16) | (b[20] << 8) | b[41], 4)
        + _to64(b[63], 2)
    )

    prefix = f"$6$rounds={rounds}$" if rounds != 5000 else "$6$"
    return f"{prefix}{salt}${hashed}"


def _make_salt(length: int = 16) -> str:
    raw = os.urandom(length)
    return "".join(_ITOA64[b & 0x3F] for b in raw)


def _hash_password(password: str) -> str:
    """SHA-512 crypt hash (shadow-compatible, no external deps)."""
    return _sha512_crypt(password, _make_salt())


def set_password_securely(username, password, chroot_path="/mnt"):
    if not username or password is None:
        logger.error("Username and password are required")
        return False
    try:
        # Preferred: chpasswd inside target (non-interactive, handles special chars).
        result = subprocess.run(
            ["chroot", chroot_path, "chpasswd"],
            input=f"{username}:{password}\n",
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            logger.info("Password set for user %s via chpasswd", username)
            return True
        logger.warning("chpasswd failed (%s), trying usermod fallback", result.stderr.strip())

        password_hash = _hash_password(password)
        result = subprocess.run(
            ["chroot", chroot_path, "usermod", "-p", password_hash, username],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            logger.info("Password set for user %s via usermod", username)
            return True
        logger.error("Failed to set password: %s", result.stderr)
        return False
    except Exception:
        logger.exception("Error setting password")
        return False
