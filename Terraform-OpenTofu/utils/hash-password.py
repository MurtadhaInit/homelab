#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "passlib",
# ]
# ///

"""
Take a password and return a sha512-crypt hash for use in Unix systems.
The salt is required for idempotency.
"""

import argparse
import json
import sys

from passlib.hash import sha512_crypt


def get_options() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Get the sha512-crypt hash for a password string",
        exit_on_error=True,
    )
    parser.add_argument("password", type=str, help="The password")
    parser.add_argument("salt", type=str, help="The salt, 0-16 chars")
    return parser.parse_args()


def main():
    args = get_options()
    hash = sha512_crypt.using(salt=args.salt).hash(secret=args.password)
    output = {"hash": hash}
    sys.stdout.write(json.dumps(output))


if __name__ == "__main__":
    main()
