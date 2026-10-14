"""Checks ref vectors.json the way harness-trace-lab makes refs: HMAC-SHA256 (or
SHA-256) over json.dumps(value, sort_keys=True, separators=(",", ":")), hex,
cut to `length`. On these inputs (ASCII text, integers, short floats) that text
is RFC 8785 canonical JSON, so V's refs and Python's agree.

    python3 -I check_vectors.py [vectors.json]   # prints the cases, exits 1 on a mismatch
    python3 -I check_vectors.py --write          # regenerates vectors.json
"""
import hashlib, hmac, json, os, sys

KEY_HEX = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
INPUTS = [
    "alice@example.com",
    "ACCT-0042",
    "",
    42,
    -7,
    0,
    0.5,
    1.25,
    True,
    False,
    None,
    [1, "two", None],
    {"to": "alice@example.com", "amount": 120, "currency": "EUR"},
    {"b": [1, {"d": 4, "c": 3}], "a": {"z": True, "y": None}},
    "quote \" backslash \\ tab \t newline \n",
]

def ref(value, key, mode, length):
    text = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    if mode == "hmac":
        return "hmac:" + hmac.new(key, text, hashlib.sha256).hexdigest()[:length]
    return "sha256:" + hashlib.sha256(text).hexdigest()[:length]

def cases():
    key = bytes.fromhex(KEY_HEX)
    out = []
    for value in INPUTS:
        for mode in ("hmac", "plain"):
            for length in (16, 32, 64):
                out.append({"input": value, "mode": mode, "length": length,
                            "canonical": json.dumps(value, sort_keys=True, separators=(",", ":")),
                            "ref": ref(value, key, mode, length)})
    return {"key_hex": KEY_HEX, "cases": out}

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "vectors.json")
    if sys.argv[1:] == ["--write"]:
        with open(path, "w") as f:
            json.dump(cases(), f, indent=1, sort_keys=True)
            f.write("\n")
        return
    if sys.argv[1:]:
        path = sys.argv[1]
    data = json.load(open(path))
    key = bytes.fromhex(data["key_hex"])
    bad = 0
    for c in data["cases"]:
        got = ref(c["input"], key, c["mode"], c["length"])
        if got != c["ref"]:
            bad += 1
            print("MISMATCH", c["input"], c["mode"], c["length"], got, c["ref"])
    print(f"{len(data['cases']) - bad}/{len(data['cases'])} cases match")
    sys.exit(1 if bad else 0)

main()
