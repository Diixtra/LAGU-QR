#!/usr/bin/env python3
"""Generate a QR code pointing to the wedding programme image.

Usage:
    python scripts/generate-qr.py <s3-view-url> [output-file]

Example:
    python scripts/generate-qr.py \
        "https://lagu-qr-abc123.s3.eu-west-2.amazonaws.com/programme.jpeg" \
        wedding-qr.png

Requires: pip install qrcode[pil]
"""

import sys

try:
    import qrcode
except ImportError:
    print("Install qrcode: pip install qrcode[pil]", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <url> [output-file]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else "wedding-qr.png"

    qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_H, box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output)
    print(f"QR code saved to {output}")
    print(f"Points to: {url}")


if __name__ == "__main__":
    main()
